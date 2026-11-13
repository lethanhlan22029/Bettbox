import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Stable Windows plugin 0.6.0 creates the Dart dispose channel with its static
/// instance ID instead of the new environment ID. Address the native instance
/// directly so closing support releases the correct browser environment.
Future<void> disposeCrispWindowsEnvironment(WebViewEnvironment environment) =>
    MethodChannel(
      'com.pichillilorenzo/flutter_webview_environment_${environment.id}',
    ).invokeMethod<void>('dispose');
