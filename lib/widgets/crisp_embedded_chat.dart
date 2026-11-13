import 'dart:async';
import 'dart:io';

import 'package:bett_box/common/crisp_support.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:synchronized/synchronized.dart';
import 'package:url_launcher/url_launcher.dart';

class CrispEmbeddedChat extends StatelessWidget {
  const CrispEmbeddedChat({
    super.key,
    required this.identity,
    required this.isCurrent,
    required this.onCreated,
    required this.onReady,
    required this.onFailure,
  });

  final CrispIdentity identity;
  final bool Function() isCurrent;
  final void Function(InAppWebViewController controller) onCreated;
  final VoidCallback onReady;
  final void Function(String message) onFailure;
  static final _storageLock = Lock();

  // This app's embedded WebView is support. Cookie cleanup does not affect
  // the panel's Dio login or system-browser cookies. Keep resets serialized.
  static Future<void> clearStorage() => _storageLock.synchronized(() async {
    await CookieManager.instance().deleteAllCookies();
    final storage = WebStorageManager.instance();
    if (Platform.isMacOS) {
      // deleteOrigin is Android-only. WKWebView uses website data records.
      final records = await storage.fetchDataRecords(
        dataTypes: WebsiteDataType.values,
      );
      final crispRecords = records.where((record) {
        final host = record.displayName?.toLowerCase();
        return host == 'crisp.chat' || (host?.endsWith('.crisp.chat') ?? false);
      }).toList();
      if (crispRecords.isNotEmpty) {
        await storage.removeDataFor(
          dataTypes: WebsiteDataType.values,
          dataRecords: crispRecords,
        );
      }
    } else {
      for (final origin in [
        'https://go.crisp.chat',
        'https://client.crisp.chat',
      ]) {
        await storage.deleteOrigin(origin: origin);
      }
    }
  });

  @override
  Widget build(BuildContext context) => InAppWebView(
    // Start empty: late platform-view creation must never load an old account.
    initialUrlRequest: URLRequest(url: WebUri('about:blank')),
    initialSettings: InAppWebViewSettings(
      javaScriptEnabled: true,
      domStorageEnabled: true,
      incognito: true,
      cacheEnabled: false,
      thirdPartyCookiesEnabled: true,
      sharedCookiesEnabled: false,
      useShouldOverrideUrlLoading: true,
      javaScriptCanOpenWindowsAutomatically: false,
      mediaPlaybackRequiresUserGesture: true,
      isInspectable: false,
    ),
    onWebViewCreated: (controller) async {
      if (!isCurrent()) return;
      onCreated(controller);
      controller.addJavaScriptHandler(
        handlerName: 'bettboxCrispState',
        callback: (args) {
          if (!isCurrent() || args.isEmpty) return;
          if (args.first == 'ready') onReady();
          if (args.first == 'error') onFailure('客服暂时无法连接，请检查网络后重试');
        },
      );
      try {
        if (!isCurrent()) return;
        final uri = WebUri(CrispSupport.chatUri()!.toString());
        await controller.loadData(
          data: CrispSupport.embeddedChatDocument(identity),
          baseUrl: uri,
          historyUrl: uri,
        );
      } on Object {
        if (isCurrent()) {
          onFailure(
            Platform.isAndroid
                ? '当前设备无法加载客服，请更新 Android System WebView 后重试'
                : '当前设备无法加载客服，请检查网络后重试',
          );
        }
      }
    },
    onReceivedError: (_, request, _) {
      if (isCurrent() &&
          request.isForMainFrame == true &&
          CrispSupport.isChatNavigation(request.url)) {
        onFailure('客服暂时无法连接，请检查网络后重试');
      }
    },
    onReceivedHttpError: (_, request, _) {
      if (isCurrent() &&
          request.isForMainFrame == true &&
          CrispSupport.isChatNavigation(request.url)) {
        onFailure('客服服务暂时不可用，请稍后重试');
      }
    },
    shouldOverrideUrlLoading: (_, navigation) async {
      if (!isCurrent()) return NavigationActionPolicy.CANCEL;
      final uri = navigation.request.url;
      if (uri == null ||
          navigation.isForMainFrame != true ||
          uri.toString() == 'about:blank') {
        return NavigationActionPolicy.ALLOW;
      }
      if (CrispSupport.isChatNavigation(uri)) {
        return NavigationActionPolicy.ALLOW;
      }
      final userActivated =
          navigation.hasGesture == true ||
          navigation.navigationType == NavigationType.LINK_ACTIVATED;
      if (uri.scheme == 'https' && uri.userInfo.isEmpty && userActivated) {
        try {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } on Object {
          // An unavailable external browser must not interrupt the chat.
        }
      }
      return NavigationActionPolicy.CANCEL;
    },
  );
}
