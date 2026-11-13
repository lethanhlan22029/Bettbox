import 'dart:async';
import 'dart:collection';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import 'crisp_support.dart';

/// A native HWND browser avoids the Windows texture/composition capture path.
class CrispWindowsBrowser extends InAppBrowser {
  CrispWindowsBrowser({
    required this.identity,
    required WebViewEnvironment environment,
    this.onReady,
    this.onProgress,
    this.onFailure,
    this.onClosed,
  }) : super(
         webViewEnvironment: environment,
         initialUserScripts: UnmodifiableListView([
           UserScript(
             source: CrispSupport.identityBootstrap(identity),
             injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
           ),
         ]),
       );

  final CrispIdentity identity;
  final void Function()? onReady;
  final void Function(int progress)? onProgress;
  final void Function(String message)? onFailure;
  final void Function()? onClosed;
  final _exited = Completer<void>();
  bool _created = false;

  bool get hasClosed => _exited.isCompleted;

  @override
  void onBrowserCreated() {
    _created = true;
    onReady?.call();
  }

  @override
  void onProgressChanged(int progress) => onProgress?.call(progress);

  @override
  void onLoadStop(WebUri? url) {
    if (url != null && CrispSupport.isChatNavigation(url)) {
      unawaited(
        webViewController
                ?.evaluateJavascript(
                  source: CrispSupport.identityUpdate(identity),
                )
                .catchError((Object _) => null) ??
            Future<void>.value(),
      );
    }
    onProgress?.call(100);
  }

  @override
  void onReceivedError(WebResourceRequest request, WebResourceError error) {
    if (request.isForMainFrame == true) onFailure?.call('客服暂时无法连接，请检查网络后重试');
  }

  @override
  void onReceivedHttpError(
    WebResourceRequest request,
    WebResourceResponse errorResponse,
  ) {
    if (request.isForMainFrame == true) onFailure?.call('客服服务暂时不可用，请稍后重试');
  }

  @override
  Future<NavigationActionPolicy?> shouldOverrideUrlLoading(
    NavigationAction navigationAction,
  ) async {
    final uri = navigationAction.request.url;
    if (uri == null ||
        navigationAction.isForMainFrame != true ||
        uri.toString() == 'about:blank') {
      return NavigationActionPolicy.ALLOW;
    }
    if (CrispSupport.isChatNavigation(uri)) return NavigationActionPolicy.ALLOW;
    if (uri.scheme == 'https' &&
        uri.userInfo.isEmpty &&
        navigationAction.hasGesture == true) {
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } on Object {
        // External links must not interrupt the support window.
      }
    }
    return NavigationActionPolicy.CANCEL;
  }

  @override
  void onExit() {
    if (!_exited.isCompleted) _exited.complete();
    onClosed?.call();
  }

  /// Only release the environment after the native window confirms exit.
  Future<bool> clearAndClose() async {
    if (hasClosed) return true;
    try {
      await webViewController
          ?.evaluateJavascript(source: CrispSupport.clearIdentity)
          .timeout(const Duration(seconds: 2));
    } on Object {
      // Closing the account-scoped window is still necessary on script failure.
    }
    if (!isOpened()) return !_created;
    try {
      await close();
      await _exited.future.timeout(const Duration(seconds: 5));
      return true;
    } on Object {
      return hasClosed;
    }
  }
}
