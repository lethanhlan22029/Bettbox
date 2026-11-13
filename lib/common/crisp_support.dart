import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'client_config.g.dart';

class CrispIdentity {
  const CrispIdentity({
    required this.token,
    required this.email,
    required this.nickname,
    required this.fields,
  });

  final String token;
  final String email;
  final String nickname;
  final Map<String, Object> fields;

  static const fieldNames = {
    'ID',
    'VIP',
    'VIP_Time',
    'Online',
    'Money',
    'Traffic',
    'Last_Time',
    'Reg_Time',
    'Update_Time',
  };

  static CrispIdentity? parse(Object? raw) {
    if (raw is! Map) return null;
    final token = raw['token'];
    final email = raw['email'];
    final nickname = raw['nickname'];
    if (token is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(token) ||
        email is! String ||
        email.length > 254 ||
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email) ||
        nickname is! String ||
        nickname.length > 256) {
      return null;
    }
    final fields = <String, Object>{};
    final data = raw['fields'];
    if (data is Map) {
      for (final name in fieldNames) {
        final value = data[name];
        if (value is String && value.length <= 512 ||
            value is bool ||
            value is num && value.isFinite) {
          fields[name] = value as Object;
        }
      }
    }
    return CrispIdentity(
      token: token,
      email: email,
      nickname: nickname.trim().isEmpty ? email : nickname,
      fields: Map.unmodifiable(fields),
    );
  }

  Map<String, Object> toJson() => {
    'token': token,
    'email': email,
    'nickname': nickname,
    'fields': fields,
  };
}

class CrispSupport {
  // Public Website ID already used by the production panel.
  static const websiteId = String.fromEnvironment(
    'CRISP_WEBSITE_ID',
    defaultValue: ClientDefaults.crispWebsiteId,
  );

  static Uri? chatUri({String id = websiteId}) {
    if (!RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(id)) {
      return null;
    }
    return Uri.https('go.crisp.chat', '/chat/embed/', {
      'website_id': id,
      'locale': 'zh',
    });
  }

  static String accountScope(String panelUrl, String email) => sha256
      .convert(
        utf8.encode(
          '${panelUrl.replaceAll(RegExp(r'/+$'), '')}/${email.trim().toLowerCase()}',
        ),
      )
      .toString();

  static bool isChatNavigation(Uri uri) =>
      uri.scheme == 'https' &&
      uri.userInfo.isEmpty &&
      uri.host == 'go.crisp.chat' &&
      uri.path.startsWith('/chat/');

  static String _json(CrispIdentity identity) => jsonEncode(identity.toJson())
      .replaceAll('<', r'\u003c')
      .replaceAll('&', r'\u0026')
      .replaceAll('\u2028', r'\u2028')
      .replaceAll('\u2029', r'\u2029');

  /// An owned document sets identity before loading the SDK, including on
  /// Android WebViews without reliable document-start UserScript support.
  static String embeddedChatDocument(
    CrispIdentity identity, {
    String id = websiteId,
  }) {
    if (chatUri(id: id) == null) throw ArgumentError.value(id, 'id');
    return '''<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
<meta name="referrer" content="no-referrer">
<title>在线客服</title>
<style>html,body{margin:0;width:100%;height:100%;font-family:sans-serif}p{text-align:center;padding:24px;color:#666}</style>
<script>
window.__bettboxCrispProfile = ${_json(identity)};
window.CRISP_WEBSITE_ID = ${jsonEncode(id)};
window.CRISP_TOKEN_ID = window.__bettboxCrispProfile.token;
window.CRISP_RUNTIME_CONFIG = {lock_full_view:true,lock_maximized:true,cross_origin_cookies:true,locale:'zh',session_merge:false};
window.\$crisp = [];
window.\$crisp.push(['set','user:email',[window.__bettboxCrispProfile.email]]);
window.\$crisp.push(['set','user:nickname',[window.__bettboxCrispProfile.nickname]]);
window.\$crisp.push(['set','session:data',[Object.entries(window.__bettboxCrispProfile.fields)]]);
window.\$crisp.push(['do','chat:open']);
window.__bettboxChatState = null;
window.__bettboxNotifyChatState = function() {
  if (window.__bettboxChatState && window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
    window.flutter_inappwebview.callHandler('bettboxCrispState', window.__bettboxChatState);
  }
};
window.addEventListener('flutterInAppWebViewPlatformReady', window.__bettboxNotifyChatState);
window.CRISP_READY_TRIGGER = function() {
  window.__bettboxChatState = 'ready';
  window.__bettboxNotifyChatState();
};
window.__bettboxChatLoadFailed = function() {
  window.__bettboxChatState = 'error';
  window.__bettboxNotifyChatState();
};
</script>
<script async src="https://client.crisp.chat/l.js" onerror="window.__bettboxChatLoadFailed()"></script>
</head><body><p>正在连接在线客服…</p></body></html>''';
  }

  static const _trustedFrame =
      "window === window.top && location.protocol === 'https:' && location.hostname === 'go.crisp.chat' && location.pathname.indexOf('/chat/') === 0";

  /// Runs before Crisp's embed loader, which replaces the async $crisp queue.
  static String identityBootstrap(CrispIdentity identity) =>
      '''
(() => {
  if (!($_trustedFrame)) return;
  window.__bettboxCrispProfile = ${_json(identity)};
  window.CRISP_TOKEN_ID = window.__bettboxCrispProfile.token;
  window.__bettboxApplyCrispProfile = function() {
    const data = window.__bettboxCrispProfile;
    const sdk = window.\$crisp;
    if (!data || !sdk || typeof sdk.get !== 'function') return false;
    try {
      sdk.push(['set', 'user:email', [data.email]]);
      sdk.push(['set', 'user:nickname', [data.nickname]]);
      sdk.push(['set', 'session:data', [Object.entries(data.fields)]]);
      return true;
    } catch (_) { return false; }
  };
  if (window.__bettboxCrispTimer) clearInterval(window.__bettboxCrispTimer);
  let attempts = 0;
  window.__bettboxCrispTimer = setInterval(() => {
    if (window.__bettboxApplyCrispProfile() || ++attempts >= 450) {
      clearInterval(window.__bettboxCrispTimer);
      window.__bettboxCrispTimer = null;
    }
  }, 100);
})();
''';

  static String identityUpdate(CrispIdentity identity) =>
      '''
(() => {
  if (!($_trustedFrame)) return false;
  if (window.__bettboxCrispProfile && window.__bettboxCrispProfile.token !== ${_json(identity)}.token) return false;
  window.__bettboxCrispProfile = ${_json(identity)};
  return window.__bettboxApplyCrispProfile ? window.__bettboxApplyCrispProfile() : false;
})();
''';

  static const clearIdentity =
      '''
(() => {
  if (!($_trustedFrame)) return;
  if (window.__bettboxCrispTimer) clearInterval(window.__bettboxCrispTimer);
  window.__bettboxCrispTimer = null;
  window.__bettboxCrispProfile = null;
  window.CRISP_TOKEN_ID = null;
  window.__bettboxChatState = null;
  window.CRISP_READY_TRIGGER = function() {};
  if (Array.isArray(window.\$crisp)) {
    // Never flush an old account's queued profile if the SDK loads after logout.
    window.\$crisp = [];
  } else if (window.\$crisp) {
    window.\$crisp.push(['do', 'session:reset']);
  }
})();
''';
}
