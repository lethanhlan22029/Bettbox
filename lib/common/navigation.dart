import 'package:bett_box/enum/enum.dart';
import 'package:bett_box/models/models.dart';
import 'package:bett_box/providers/providers.dart';
import 'package:bett_box/views/views.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'metron_policy.dart';
import 'package:bett_box/views/metron_account.dart';
import 'package:bett_box/views/metron_support.dart';

class Navigation {
  static Navigation? _instance;

  List<NavigationItem> getItems({
    bool openLogs = false,
    bool hasProxies = false,
  }) {
    return [
      NavigationItem(
        keep: false,
        icon: const Icon(Icons.home),
        label: PageLabel.dashboard,
        builder: (_) =>
            DashboardView(key: const GlobalObjectKey(PageLabel.dashboard)),
      ),
      NavigationItem(
        icon: const Icon(Icons.explore),
        label: PageLabel.proxies,
        builder: (_) => ProviderScope(
          overrides: [queryProvider.overrideWith(() => Query())],
          child: ProxiesView(
            key: const GlobalObjectKey(PageLabel.proxies),
            showSettings: false,
          ),
        ),
        modes: hasProxies
            ? [NavigationItemMode.mobile, NavigationItemMode.desktop]
            : [],
      ),
      NavigationItem(
        icon: const Icon(Icons.folder_shared),
        label: PageLabel.profiles,
        builder: (_) =>
            ProfilesView(key: const GlobalObjectKey(PageLabel.profiles)),
      ),
      NavigationItem(
        icon: Icon(Icons.cable_rounded),
        label: PageLabel.connections,
        builder: (_) =>
            ConnectionsView(key: const GlobalObjectKey(PageLabel.connections)),
        description: 'connectionsDesc',
        modes: [NavigationItemMode.desktop, NavigationItemMode.mobile],
      ),
      NavigationItem(
        icon: const Icon(Icons.storage),
        label: PageLabel.resources,
        description: 'resourcesDesc',
        builder: (_) =>
            ResourcesView(key: const GlobalObjectKey(PageLabel.resources)),
        modes: [NavigationItemMode.more],
      ),
      NavigationItem(
        icon: const Icon(Icons.terminal_outlined),
        label: PageLabel.script,
        description: 'scriptDesc',
        builder: (_) =>
            ScriptsView(key: const GlobalObjectKey(PageLabel.script)),
        modes: [NavigationItemMode.more],
      ),
      NavigationItem(
        icon: const Icon(Icons.handyman_outlined),
        label: PageLabel.toolbox,
        description: 'toolboxDesc',
        builder: (_) =>
            ToolboxView(key: const GlobalObjectKey(PageLabel.toolbox)),
        modes: [NavigationItemMode.desktop, NavigationItemMode.mobile],
      ),
      NavigationItem(
        icon: const Icon(Icons.adb_rounded),
        label: PageLabel.logs,
        builder: (_) => LogsView(key: const GlobalObjectKey(PageLabel.logs)),
        description: 'logsDesc',
        modes: [NavigationItemMode.desktop, NavigationItemMode.mobile],
      ),
      NavigationItem(
        icon: const Icon(Icons.account_circle_outlined),
        label: PageLabel.account,
        builder: (_) =>
            const MetronAccountView(key: GlobalObjectKey(PageLabel.account)),
        modes: [NavigationItemMode.desktop, NavigationItemMode.mobile],
      ),
      NavigationItem(
        icon: const Icon(Icons.support_agent),
        label: PageLabel.support,
        builder: (_) =>
            const MetronSupportView(key: GlobalObjectKey(PageLabel.support)),
        modes: [NavigationItemMode.desktop, NavigationItemMode.mobile],
      ),
      NavigationItem(
        icon: Icon(Icons.construction),
        label: PageLabel.tools,
        builder: (_) => ToolsView(key: const GlobalObjectKey(PageLabel.tools)),
        modes: [NavigationItemMode.desktop, NavigationItemMode.mobile],
      ),
    ].where((item) => metronUsagePages.contains(item.label)).toList();
  }

  Navigation._internal();

  factory Navigation() {
    _instance ??= Navigation._internal();
    return _instance!;
  }
}

final navigation = Navigation();
