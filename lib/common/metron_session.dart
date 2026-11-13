import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:synchronized/synchronized.dart';

import 'identity.dart';
import 'crisp_support.dart';
import 'client_config.g.dart';
import 'metron_session_store.dart';
import 'metron_account.dart';

class MetronException implements Exception {
  const MetronException(this.message);
  final String message;
  @override
  String toString() => message;
}

MetronException metronFailure(Object error, String stage) {
  if (error is MetronException) return error;
  String reason;
  if (error is DioException) {
    final status = error.response?.statusCode;
    if (status != null) {
      reason = 'HTTP $status，请检查订阅服务的响应';
    } else if (error.type == DioExceptionType.badCertificate) {
      reason = 'HTTPS 证书验证失败';
    } else if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      reason = '网络请求超时';
    } else {
      reason = '网络连接失败，请检查订阅域名和网络';
    }
  } else if (error is FileSystemException) {
    reason = '无法读写本地文件，请检查目录权限和磁盘空间';
  } else if (error is FormatException) {
    reason = '返回内容格式无效，请检查是否为 Clash YAML 订阅';
  } else if (error is String) {
    // Core validation errors may contain subscription URLs or config snippets.
    final lines = error.split(RegExp(r'[\r\n]+'));
    // YAML's first line is only a heading. Keep the following line/type errors
    // so a subscription mismatch can actually be diagnosed.
    final details = error.contains('yaml: unmarshal errors:')
        ? [
            lines.first,
            ...lines
                .skip(1)
                .where((line) => RegExp(r'^\s*line \d+:').hasMatch(line))
                .take(6),
          ].join('\n')
        : lines.first;
    reason = details
        .replaceAll(RegExp(r'https?://\S+', caseSensitive: false), '[地址已隐藏]')
        .replaceAll(RegExp(r'`[^`]*`'), '[内容已隐藏]')
        .replaceAllMapped(
          RegExp(
            r'(password|passwd|token|secret|uuid|authorization)\s*[:=]\s*[^,;\s]+',
            caseSensitive: false,
          ),
          (match) => '${match[1]}=[已隐藏]',
        );
    if (reason.length > 1000) reason = '${reason.substring(0, 1000)}…';
    if (reason.isEmpty) reason = '内核返回空错误信息';
  } else {
    reason = '客户端异常（${error.runtimeType}）';
  }
  return MetronException('$stage失败：$reason');
}

/// Persist only the token; a restored session must be verified by the panel.
class MetronSession extends ChangeNotifier {
  static const accountRefreshInterval = Duration(minutes: 1);
  MetronSession({Dio? dio, MetronSessionStore? store})
    : _dio = dio ?? Dio(),
      _store = store ?? const SecureMetronSessionStore() {
    _dio.options.connectTimeout = const Duration(seconds: 20);
  }

  static const panelUrl = String.fromEnvironment(
    'METRON_BASE_URL',
    defaultValue: ClientDefaults.panelUrl,
  );
  static const subscriptionBaseUrl = String.fromEnvironment(
    'METRON_SUBSCRIPTION_BASE_URL',
    defaultValue: ClientDefaults.subscriptionBaseUrl,
  );
  final Dio _dio;
  final MetronSessionStore _store;
  final _storageLock = Lock();
  String get _storageKey =>
      'metron.${AppIdentity.dataDirName}.${sha256.convert(utf8.encode(panelUrl.replaceAll(RegExp(r'/+$'), '')))}';
  int _revision = 0;
  int get generation => _revision;
  bool _verified = false;
  bool restoring = false;
  bool canRestore = false;
  String? restoreError;
  String? _token;
  DateTime? _expiresAt;
  Timer? _expiryTimer;
  String email = '';
  MetronAccount? account;
  DateTime? accountUpdatedAt;
  DateTime? _nextAccountRefreshAt;
  Future<Map>? _sessionRequest;
  int? _sessionRequestRevision;
  bool _ready = false;
  bool get hasSession =>
      _verified &&
      _token != null &&
      (_expiresAt?.isAfter(DateTime.now()) ?? false);
  bool get authenticated => _ready && hasSession;
  VoidCallback? onExpired;

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> data,
  ) async {
    final requestRevision = _revision;
    final requestToken = data['access_token'];
    final base = Uri.tryParse(panelUrl);
    if (base == null ||
        base.scheme != 'https' ||
        base.host.isEmpty ||
        base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment) {
      throw const MetronException('面板地址配置错误，请联系管理员');
    }
    try {
      final response = await _dio.post<String>(
        '${panelUrl.replaceAll(RegExp(r'/+$'), '')}$path',
        data: data,
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.plain,
          followRedirects: false,
          sendTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );
      final body = jsonDecode(response.data ?? '') as Map<String, dynamic>;
      if (body['ret'] != 1) {
        // A response from an old account must never revoke a newer login.
        if (body['ret'] == -1 &&
            requestRevision == _revision &&
            requestToken is String &&
            requestToken == _token) {
          await clear();
        }
        throw MetronException(body['msg'] as String? ?? '请求失败，请重试');
      }
      return body;
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      final prefix = '接口 $path';
      if (status != null) {
        if (status >= 300 && status < 400) {
          final location = error.response?.headers.value('location');
          final target = location == null ? null : Uri.tryParse(location)?.path;
          final hint = target == '/500'
              ? '服务端发生异常，请检查 PHP 错误日志和接口部署'
              : '接口发生跳转，请检查面板地址和路由配置';
          throw MetronException('$prefix：HTTP $status，$hint');
        }
        if (status == 404 || status == 405) {
          throw MetronException('$prefix：HTTP $status，请检查客户端接口是否已部署');
        }
        if (status == 403) {
          throw MetronException('$prefix：HTTP 403，请检查站点访问限制或防火墙规则');
        }
        if (status >= 500) {
          throw MetronException('$prefix：HTTP $status，请检查面板 PHP 错误日志');
        }
        throw MetronException('$prefix：HTTP $status，请检查面板响应');
      }
      if (error.type == DioExceptionType.badCertificate) {
        throw MetronException('$prefix：HTTPS 证书验证失败，请检查证书及系统时间');
      }
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.receiveTimeout) {
        throw MetronException('$prefix：请求超时，请检查网络后重试');
      }
      throw MetronException('$prefix：连接失败，请检查域名解析、网络或 HTTPS 连接');
    } on FormatException {
      throw MetronException('接口 $path 未返回有效 JSON，请检查接口部署或站点验证页面');
    } on TypeError {
      throw const MetronException('面板响应异常，请联系管理员检查客户端接口');
    }
  }

  Future<void> login(String account, String password, String code) async {
    await clear();
    final revision = _revision;
    final body = await _post('/api/client/login', {
      'email': account.trim().toLowerCase(),
      'passwd': password,
      'code': code.trim(),
    });
    final data = body['data'];
    final token = data is Map ? data['token'] : null;
    if (token is! String || token.isEmpty) {
      throw const MetronException('登录响应无效');
    }
    if (revision != _revision) throw const MetronException('登录已取消，请重试');
    _token = token;
    email = account.trim();
  }

  Future<String> subscription() async {
    final data = await _fetchSession();
    return data['subscription_url'] as String;
  }

  Future<void> refreshAccount({bool ifStale = false}) async {
    if (!authenticated) throw const MetronException('请先登录');
    if (ifStale &&
        _nextAccountRefreshAt != null &&
        DateTime.now().isBefore(_nextAccountRefreshAt!)) {
      return;
    }
    await _fetchSession();
  }

  Future<CrispIdentity> supportIdentity() async {
    if (!authenticated) throw const MetronException('请先登录后联系客服');
    final revision = _revision;
    final body = await _post('/api/client/support', {'access_token': _token});
    if (revision != _revision || !authenticated) {
      throw const MetronException('登录已失效，请重新登录');
    }
    final identity = CrispIdentity.parse(body['data']);
    if (identity == null) throw const MetronException('客服账号资料无效，请检查客户端客服接口部署');
    return identity;
  }

  Future<Map> _fetchSession() {
    if (_token == null) throw const MetronException('请先登录');
    if (_sessionRequest != null && _sessionRequestRevision == _revision) {
      return _sessionRequest!;
    }
    _nextAccountRefreshAt = DateTime.now().add(accountRefreshInterval);
    _sessionRequestRevision = _revision;
    late Future<Map> request;
    request = _requestSession().whenComplete(() {
      if (identical(_sessionRequest, request)) _sessionRequest = null;
    });
    return _sessionRequest = request;
  }

  Future<Map> _requestSession() async {
    final revision = _revision;
    final body = await _post('/api/client/session', {'access_token': _token});
    if (revision != _revision) throw const MetronException('登录已失效，请重新登录');
    final data = body['data'];
    if (data is! Map || data['subscription_url'] is! String) {
      throw const MetronException('会话接口响应缺少订阅地址，请检查面板接口部署');
    }
    var uri = Uri.tryParse(data['subscription_url'] as String);
    final expiry = int.tryParse('${data['expire_time']}');
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        expiry == null ||
        expiry * 1000 <= DateTime.now().millisecondsSinceEpoch) {
      throw const MetronException('订阅或登录有效期无效，请联系管理员');
    }
    if (subscriptionBaseUrl.isNotEmpty) {
      final base = Uri.tryParse(subscriptionBaseUrl);
      if (base == null ||
          base.scheme != 'https' ||
          base.host.isEmpty ||
          base.userInfo.isNotEmpty ||
          (base.path.isNotEmpty && base.path != '/') ||
          base.hasQuery ||
          base.hasFragment) {
        throw const MetronException('订阅域名配置错误，请联系管理员');
      }
      // Keep the panel-issued token path and query; only the origin changes.
      uri = uri.replace(scheme: base.scheme, host: base.host, port: base.port);
    }
    _expiresAt = DateTime.fromMillisecondsSinceEpoch(expiry * 1000);
    _verified = true;
    _expiryTimer?.cancel();
    _expiryTimer = Timer(_expiresAt!.difference(DateTime.now()), () {
      unawaited(clear().catchError((Object _) {}));
    });
    account = MetronAccount.parse(data['account']);
    accountUpdatedAt = DateTime.now();
    notifyListeners();
    return {...data, 'subscription_url': uri.toString()};
  }

  Future<void> activate() async {
    if (!hasSession) {
      throw const MetronException('登录已失效，请重新登录');
    }
    final revision = _revision;
    final record = jsonEncode({
      'version': 1,
      'panel': panelUrl,
      'email': email,
      'token': _token,
      'expiresAt': _expiresAt!.millisecondsSinceEpoch,
    });
    try {
      await _storageLock.synchronized(() => _store.write(_storageKey, record));
    } on Object {
      throw const MetronException('无法安全保存登录信息，请检查系统凭据存储后重试');
    }
    if (revision != _revision || !hasSession) {
      throw const MetronException('登录已失效，请重新登录');
    }
    _ready = true;
    canRestore = true;
    restoreError = null;
    notifyListeners();
  }

  void _clearMemory() {
    final wasReady = _ready;
    _revision++;
    _ready = false;
    _verified = false;
    _token = null;
    _expiresAt = null;
    email = '';
    account = null;
    accountUpdatedAt = null;
    _nextAccountRefreshAt = null;
    _expiryTimer?.cancel();
    if (wasReady) onExpired?.call();
  }

  Future<void> clear() {
    _clearMemory();
    canRestore = false;
    restoreError = null;
    notifyListeners();
    return _storageLock.synchronized(() => _store.delete(_storageKey));
  }

  Future<void> restore(Future<void> Function() prepare) async {
    if (restoring || authenticated) return;
    restoring = true;
    canRestore = true;
    restoreError = null;
    notifyListeners();
    final revision = _revision;
    try {
      final raw = await _storageLock.synchronized(
        () => _store.read(_storageKey),
      );
      if (revision != _revision) return;
      if (raw == null) {
        canRestore = false;
        return;
      }
      Map<String, dynamic> record;
      try {
        record = jsonDecode(raw) as Map<String, dynamic>;
        if (record['version'] != 1 ||
            record['panel'] != panelUrl ||
            record['token'] is! String ||
            (record['token'] as String).isEmpty ||
            record['email'] is! String ||
            record['expiresAt'] is! int ||
            (record['expiresAt'] as int) <=
                DateTime.now().millisecondsSinceEpoch) {
          await clear();
          return;
        }
      } on FormatException {
        await clear();
        return;
      } on TypeError {
        await clear();
        return;
      }
      _token = record['token'] as String;
      email = record['email'] as String;
      canRestore = true;
      // prepare must fetch the session endpoint and import/validate its subscription.
      await prepare();
      await activate();
    } on Object catch (error) {
      if (revision == _revision) {
        _clearMemory();
        restoreError = metronFailure(error, '自动登录').message;
      }
    } finally {
      restoring = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    final token = _token;
    final clearing = clear();
    try {
      await clearing;
    } finally {
      if (token != null) {
        try {
          await _post('/api/client/logout', {'access_token': token});
        } on Object {
          // Local access has already been revoked, even if the network is down.
        }
      }
    }
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    _dio.close(force: true);
    super.dispose();
  }
}

final metronSession = MetronSession();
