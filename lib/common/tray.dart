import 'dart:async';
import 'dart:io';

import 'package:bett_box/models/models.dart';
import 'package:bett_box/state.dart';
import 'package:bett_box/views/proxies/common.dart';
import 'package:material_ui/material_ui.dart';


import 'package:tray_manager/tray_manager.dart';


import 'common.dart';
import 'metron_session.dart';

class Tray {
  Timer? _debounceTimer;
  TrayState? _pendingState;
  bool _isUpdating = false;
  bool _pendingFocus = false;
  bool _pendingSilent = false;
  bool showHiddenGroups = false;

  static const _debounceDelay = Duration(milliseconds: 300);





  Tray() {
    delayTestCoordinator.addListener(_handleDelayTestStateChanged);
  }

  void _handleDelayTestStateChanged() {
    if (system.isAndroid) return;
    unawaited(globalState.appController.updateTray(false, true));
  }

  bool _traySpeedEnabled = false;
  bool _trayTrafficActive = false;
  bool _isSpeedTitleVisible = false;
  Traffic _lastTraffic = Traffic();
  int? _lastDisplayedUpload;
  int? _lastDisplayedDownload;
  bool? _lastDisplayedActive;

  void dispose() {
    delayTestCoordinator.removeListener(_handleDelayTestStateChanged);
    _debounceTimer?.cancel();

  }

  Future _updateSystemTray({
    required Brightness? brightness,
    required bool isStart,
    bool force = false,
  }) async {
    if (system.isAndroid) {
      return;
    }
    if (force) {
      await trayManager.destroy();
      _isSpeedTitleVisible = false;
      _lastDisplayedUpload = null;
      _lastDisplayedDownload = null;
      _lastDisplayedActive = null;
    }
    await trayManager.setIcon(
      utils.getTrayIconPath(
        brightness:
            brightness ??
            WidgetsBinding.instance.platformDispatcher.platformBrightness,
        isStart: isStart,
        invertTrayIcon:
            (system.isWindows || (system.isMacOS && !isStart)) &&
            globalState.config.themeProps.invertTrayIcon,
      ),
      isTemplate: system.isMacOS && isStart,
      id: AppIdentity.compactName,
    );
    if (system.isMacOS) {
      await trayManager.setActive(isStart);
    }
    if (!Platform.isLinux) {
      await trayManager.setToolTip(appName);
    }
  }

  Future<void> update({
    required TrayState trayState,
    bool focus = false,
    bool silent = false,
    bool force = false,
  }) async {
    if (system.isAndroid) {
      return;
    }

    _debounceTimer?.cancel();

    if (_isUpdating) {
      _pendingState = trayState;
      _pendingFocus = focus;
      _pendingSilent = silent;
      return;
    }

    if (force || focus) {
      await _doUpdate(trayState: trayState, focus: focus, silent: silent);
    } else if (silent) {
      _debounceTimer = Timer(const Duration(milliseconds: 50), () async {
        await _doUpdate(trayState: trayState, focus: focus, silent: silent);
      });
    } else {
      _debounceTimer = Timer(_debounceDelay, () async {
        await _doUpdate(trayState: trayState, focus: focus);
      });
    }
  }

  Future<void> _doUpdate({
    required TrayState trayState,
    bool focus = false,
    bool silent = false,
  }) async {
    if (_isUpdating) return;
    _isUpdating = true;

    try {
      _traySpeedEnabled = trayState.enableTraySpeed;
      _trayTrafficActive =
          trayState.isStart && (trayState.systemProxy || trayState.tunEnable);
      if (!silent && !Platform.isLinux) {
        await _updateSystemTray(
          brightness: trayState.brightness,
          isStart: _trayTrafficActive,
          force: focus,
        );
      }
      if (system.isMacOS) {
        await _syncSpeedTitle(isStart: trayState.isStart);
      }
      List<MenuItem> menuItems = [];
      final showMenuItem = MenuItem(
        label: appLocalizations.show,
        onClick: (_) {
          window?.show();
        },
      );
      menuItems.add(showMenuItem);
      final startMenuItem = MenuItem.checkbox(
        disabled: !metronSession.authenticated,
        label: trayState.isStart
            ? appLocalizations.stop
            : appLocalizations.start,
        onClick: (_) async {
          final appController = globalState.appController;
          await appController.updateStatus(!globalState.isStart);
          await appController.updateTray(false, false, true);
        },
        checked: false,
      );
      menuItems.add(startMenuItem);
      menuItems.add(MenuItem.separator());
      final exitMenuItem = MenuItem(
        label: appLocalizations.exit,
        onClick: (_) async {
          await globalState.appController.handleExit();
        },
      );
      menuItems.add(exitMenuItem);
      final menu = Menu(items: menuItems);
      await trayManager.setContextMenu(
        menu,
        keepMenuOpen: silent || system.isWindows,
        brightness: trayState.brightness,
      );
      if (Platform.isLinux) {
        await _updateSystemTray(
          brightness: trayState.brightness,
          isStart: trayState.isStart,
          force: focus,
        );
      }
    } finally {
      _isUpdating = false;

      if (_pendingState != null) {
        final pending = _pendingState;
        final pendingFocus = _pendingFocus;
        final pendingSilent = _pendingSilent;
        _pendingState = null;
        _pendingFocus = false;
        _pendingSilent = false;
        await _doUpdate(
          trayState: pending!,
          focus: pendingFocus,
          silent: pendingSilent,
        );
      }
    }
  }

  Future<void> updateSpeed(Traffic traffic) async {
    _lastTraffic = traffic;
    if (!system.isMacOS || !_traySpeedEnabled) {
      return;
    }
    await _setSpeedTitle(traffic);
  }

  Future<void> _syncSpeedTitle({required bool isStart}) async {
    if (!_traySpeedEnabled) {
      if (!_isSpeedTitleVisible) {
        return;
      }
      await trayManager.clearSpeedTitle();
      _isSpeedTitleVisible = false;
      _lastDisplayedUpload = null;
      _lastDisplayedDownload = null;
      _lastDisplayedActive = null;
      return;
    }

    if (!isStart) {
      _lastTraffic = Traffic();
    }
    await _setSpeedTitle(_lastTraffic);
  }

  Future<void> _setSpeedTitle(Traffic traffic) async {
    final upload = traffic.up.value;
    final download = traffic.down.value;
    if (_isSpeedTitleVisible &&
        _lastDisplayedUpload == upload &&
        _lastDisplayedDownload == download &&
        _lastDisplayedActive == _trayTrafficActive) {
      return;
    }
    await trayManager.setSpeedTitle(
      upload: upload,
      download: download,
      active: _trayTrafficActive,
    );
    _isSpeedTitleVisible = true;
    _lastDisplayedUpload = upload;
    _lastDisplayedDownload = download;
    _lastDisplayedActive = _trayTrafficActive;
  }

}

final tray = Tray();
