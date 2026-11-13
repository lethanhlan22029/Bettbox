import 'dart:async';
import 'dart:io';

import 'package:bett_box/common/common.dart';
import 'package:bett_box/common/crisp_support.dart';
import 'package:bett_box/common/crisp_webview_environment.dart';
import 'package:bett_box/common/crisp_windows_browser.dart';
import 'package:bett_box/common/metron_session.dart';
import 'package:bett_box/enum/enum.dart';
import 'package:bett_box/providers/providers.dart';
import 'package:bett_box/widgets/widgets.dart';
import 'package:bett_box/widgets/crisp_embedded_chat.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as path;
import 'package:url_launcher/url_launcher.dart';

class MetronSupportView extends ConsumerStatefulWidget {
  const MetronSupportView({super.key});
  @override
  ConsumerState<MetronSupportView> createState() => _MetronSupportViewState();
}

class _MetronSupportViewState extends ConsumerState<MetronSupportView> {
  WebViewEnvironment? _environment;
  CrispWindowsBrowser? _browser;
  InAppWebViewController? _embeddedController;
  CrispIdentity? _identity;
  Future<void>? _opening;
  Future<void> _releasing = Future<void>.value();
  bool _windowOpen = false;
  String? _scope;
  int _generation = -1;
  Timer? _loadTimer;
  bool _started = false;
  bool _ready = false;
  bool _preparing = false;
  bool _runtimeMissing = false;
  double _progress = 0;
  int _attempt = 0;
  String? _error;
  final _uri = CrispSupport.chatUri();

  bool get _canEmbed => system.isWindows || _usesEmbeddedChat;
  bool get _usesEmbeddedChat => system.isAndroid || system.isMacOS;

  String get _currentScope =>
      CrispSupport.accountScope(MetronSession.panelUrl, metronSession.email);

  @override
  void initState() {
    super.initState();
    metronSession.addListener(_sessionChanged);
  }

  void _sessionChanged() {
    if (_scope == null ||
        mounted &&
            metronSession.authenticated &&
            _scope == _currentScope &&
            _generation == metronSession.generation) {
      return;
    }
    _clearBinding();
  }

  void _clearBinding({bool rebuild = true}) {
    _loadTimer?.cancel();
    final browser = _browser;
    final opening = _opening;
    final environment = _environment;
    final embeddedController = _embeddedController;
    final clearEmbedded = _usesEmbeddedChat && _scope != null;
    final embeddedReset = embeddedController
        ?.evaluateJavascript(source: CrispSupport.clearIdentity)
        .timeout(const Duration(seconds: 2))
        .catchError((Object _) => null);
    _embeddedController = null;
    _identity = null;
    _browser = null;
    _opening = null;
    _environment = null;
    _scope = null;
    _generation = -1;
    _attempt++;
    _ready = false;
    _started = false;
    _preparing = false;
    _windowOpen = false;
    _progress = 0;
    _error = null;
    if (mounted && rebuild) setState(() {});
    _releasing = _releasing
        .then((_) async {
          try {
            await opening;
          } on Object {
            /* An unsuccessful open still needs cleanup. */
          }
          await embeddedReset;
          if (clearEmbedded) await CrispEmbeddedChat.clearStorage();
          final closed = browser == null || await browser.clearAndClose();
          if (environment != null && closed) {
            await disposeCrispWindowsEnvironment(environment);
          }
        })
        .catchError((Object _) {
          commonPrint.warn('Support window cleanup failed');
        });
  }

  Future<void> _initialize() async {
    if (_preparing) return;
    _preparing = true;
    _runtimeMissing = false;
    final attempt = _attempt;
    final revision = metronSession.generation;
    bool current() =>
        mounted && attempt == _attempt && revision == metronSession.generation;
    try {
      await _releasing;
      if (!current()) return;
      if (_uri == null) {
        _fail('客服暂未开通，请稍后再试');
        return;
      }
      if (!_canEmbed) {
        _fail('当前设备暂不支持应用内客服');
        return;
      }
      if (!metronSession.authenticated) {
        _fail('请先登录后联系客服');
        return;
      }
      _scope = _currentScope;
      _generation = revision;
      final identity = await metronSession.supportIdentity();
      if (!current()) return;
      _identity = identity;
      if (_usesEmbeddedChat) {
        await CrispEmbeddedChat.clearStorage();
        if (!current()) return;
        setState(() {
          _ready = true;
          _error = null;
        });
        _watchLoad();
        return;
      }
      if (system.isWindows && _environment == null) {
        if (await WebViewEnvironment.getAvailableVersion() == null) {
          _runtimeMissing = true;
          _fail('当前设备缺少聊天组件，请安装组件后重试');
          return;
        }
        final root = await appPath.dataDir.future;
        final folder = Directory(
          path.join(
            root.path,
            'support',
            CrispSupport.accountScope(
              MetronSession.panelUrl,
              metronSession.email,
            ),
          ),
        );
        await folder.create(recursive: true);
        final environment = await WebViewEnvironment.create(
          settings: WebViewEnvironmentSettings(userDataFolder: folder.path),
        );
        if (!current()) {
          await disposeCrispWindowsEnvironment(environment);
          return;
        }
        _environment = environment;
      }
      if (!current()) return;
      final browser = CrispWindowsBrowser(
        identity: identity,
        environment: _environment!,
        onReady: () {
          if (current()) setState(() => _windowOpen = true);
        },
        onProgress: (progress) {
          if (!current()) return;
          if (progress >= 100) _loadTimer?.cancel();
          setState(() => _progress = progress / 100);
        },
        onFailure: (message) {
          if (current()) _fail(message);
        },
        onClosed: () {
          if (!current()) return;
          _loadTimer?.cancel();
          setState(() {
            _windowOpen = false;
            _progress = 1;
          });
        },
      );
      _browser = browser;
      _watchLoad();
      final opening = browser.openUrlRequest(
        urlRequest: URLRequest(url: WebUri(_uri.toString())),
        settings: InAppBrowserClassSettings(
          browserSettings: InAppBrowserSettings(hideUrlBar: true),
          webViewSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            useShouldOverrideUrlLoading: true,
            javaScriptCanOpenWindowsAutomatically: false,
            isInspectable: false,
          ),
        ),
      );
      _opening = opening;
      await opening;
      if (!current()) return;
      _opening = null;
      setState(() {
        _ready = true;
        _windowOpen = browser.isOpened();
        _error = null;
      });
    } on Object catch (error) {
      if (current()) {
        _fail(error is MetronException ? error.message : '当前设备暂时无法显示在线客服，请重试');
      }
    } finally {
      if (current()) _preparing = false;
    }
  }

  void _watchLoad() {
    _loadTimer?.cancel();
    if (!mounted ||
        !system.isWindows &&
            ref.read(currentPageLabelProvider) != PageLabel.support) {
      return;
    }
    _loadTimer = Timer(
      const Duration(seconds: 45),
      () => _fail('客服加载超时，请检查网络后重试'),
    );
  }

  void _fail(String message) {
    _loadTimer?.cancel();
    if (mounted) setState(() => _error = message);
  }

  void _retry() {
    if (_preparing) return;
    _clearBinding();
    _started = true;
    unawaited(_initialize());
  }

  Future<void> _showWindow() async {
    final browser = _browser;
    if (browser == null || !browser.isOpened()) {
      _retry();
      return;
    }
    try {
      await browser.show();
    } on Object {
      _fail('无法显示客服窗口，请重试');
    }
  }

  @override
  void dispose() {
    metronSession.removeListener(_sessionChanged);
    _clearBinding(rebuild: false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(currentPageLabelProvider) == PageLabel.support;
    if (!active) {
      // Windows chat owns a separate native window. Keep its account binding
      // and load callbacks alive while the user navigates the main app.
      if (!system.isWindows) {
        _loadTimer?.cancel();
        if (_started) _clearBinding(rebuild: false);
      }
      return const SizedBox.shrink();
    }
    if (!_started) {
      _started = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_initialize());
      });
    }
    return CommonScaffold(
      title: '联系支持',
      backgroundColor: Theme.of(context).colorScheme.surface,
      actions: [
        IconButton(
          tooltip: '重新加载客服',
          onPressed: _preparing ? null : _retry,
          icon: const Icon(Icons.refresh),
        ),
      ],
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Row(
              children: [
                Icon(Icons.support_agent, size: 26),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${AppIdentity.brandName}在线客服',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      SizedBox(height: 4),
                      Text('套餐、订阅或连接遇到问题，都可以在这里咨询。'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: _error != null
                    ? _fallback(context)
                    : !_ready
                    ? const Center(child: CircularProgressIndicator())
                    : Stack(
                        children: [
                          Positioned.fill(
                            child: _usesEmbeddedChat
                                ? _embeddedChat()
                                : _nativeWindowStatus(context),
                          ),

                          if (_progress < 1)
                            LinearProgressIndicator(
                              value: _progress == 0 ? null : _progress,
                            ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _embeddedChat() {
    final attempt = _attempt;
    final generation = _generation;
    bool current() =>
        mounted &&
        _ready &&
        _error == null &&
        attempt == _attempt &&
        generation == metronSession.generation &&
        metronSession.authenticated &&
        _scope == _currentScope &&
        ref.read(currentPageLabelProvider) == PageLabel.support;
    return CrispEmbeddedChat(
      key: ValueKey('embedded-support-$attempt'),
      identity: _identity!,
      isCurrent: current,
      onCreated: (controller) {
        if (current()) _embeddedController = controller;
      },
      onReady: () {
        if (!current()) return;
        _loadTimer?.cancel();
        setState(() => _progress = 1);
      },
      onFailure: (message) {
        if (current()) _fail(message);
      },
    );
  }

  Widget _nativeWindowStatus(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.support_agent,
            size: 48,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            _windowOpen ? '客服已在独立窗口打开' : '客服窗口已关闭',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text('客服窗口会同步当前账号资料，切换页面可继续聊天。', textAlign: TextAlign.center),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _showWindow,
            icon: const Icon(Icons.chat_outlined),
            label: Text(_windowOpen ? '显示客服窗口' : '重新打开客服'),
          ),
        ],
      ),
    ),
  );

  Widget _fallback(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.chat_bubble_outline_rounded,
            size: 48,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              if (_uri != null && _canEmbed)
                OutlinedButton(onPressed: _retry, child: const Text('重新加载')),
              if (_runtimeMissing)
                TextButton(
                  onPressed: () async {
                    await launchUrl(
                      Uri.parse(
                        'https://developer.microsoft.com/microsoft-edge/webview2/',
                      ),
                      mode: LaunchMode.externalApplication,
                    );
                  },
                  child: const Text('安装聊天组件'),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}
