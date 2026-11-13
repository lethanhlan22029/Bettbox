import 'package:bett_box/common/common.dart';
import 'package:bett_box/clash/core.dart';
import 'package:bett_box/common/metron_session.dart';
import 'package:bett_box/pages/pages.dart';
import 'package:bett_box/providers/providers.dart';
import 'package:bett_box/state.dart';
import 'package:bett_box/widgets/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class MetronDiagnosticsView extends ConsumerStatefulWidget {
  const MetronDiagnosticsView({super.key});
  @override
  ConsumerState<MetronDiagnosticsView> createState() =>
      _MetronDiagnosticsViewState();
}

class _MetronDiagnosticsViewState extends ConsumerState<MetronDiagnosticsView> {
  bool _checking = false;
  String _panelStatus = '尚未检查';
  String _nodeStatus = '尚未检查';

  Future<void> _checkNode() async {
    if (_checking) return;
    final groups = ref.read(groupsProvider);
    final current = ref.read(currentProfileProvider)?.currentGroupName;
    final group =
        groups.where((g) => g.name == current).firstOrNull ??
        groups.firstOrNull;
    if (group == null) {
      setState(() => _nodeStatus = '没有可测试的节点，请先更新订阅');
      return;
    }
    final target = ref.read(getProxyNameProvider(group.name)) ?? group.name;
    setState(() => _checking = true);
    try {
      final delay = await clashCore.getDelay(
        ref.read(appSettingProvider).testUrl,
        target,
      );
      if (mounted) {
        setState(
          () => _nodeStatus = (delay.value ?? -1) > 0
              ? '可用，延迟 ${delay.value} ms'
              : '节点超时，请切换节点后重试',
        );
      }
    } on Object {
      if (mounted) setState(() => _nodeStatus = '测试失败，请检查网络或切换节点');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _checkPanel() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      await metronSession.refreshAccount();
      if (mounted) setState(() => _panelStatus = '连接正常，会话有效');
    } on Object catch (error) {
      if (mounted) {
        setState(() => _panelStatus = metronFailure(error, '面板连接').message);
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final running = ref.watch(runTimeProvider) != null;
    final hasProfile = ref.watch(currentProfileProvider) != null;
    final proxy = ref.watch(
      networkSettingProvider.select((s) => s.systemProxy),
    );
    final tun = ref.watch(patchClashConfigProvider.select((s) => s.tun.enable));
    final route = tun
        ? '增强模式（TUN）'
        : proxy
        ? '系统代理'
        : '未启用系统代理或增强模式';
    return CommonScaffold(
      title: '网络诊断',
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          ListTile(
            title: const Text('连接状态'),
            subtitle: Text(running ? '已连接' : '未连接'),
          ),
          ListTile(
            title: const Text('订阅状态'),
            subtitle: Text(hasProfile ? '已加载订阅' : '尚未加载，请到账号页更新订阅'),
          ),
          ListTile(title: const Text('代理接管方式'), subtitle: Text(route)),
          ListTile(title: const Text('面板连接'), subtitle: Text(_panelStatus)),
          ListTile(title: const Text('节点连通性'), subtitle: Text(_nodeStatus)),
          FilledButton.icon(
            onPressed: _checking ? null : _checkPanel,
            icon: const Icon(Icons.network_check),
            label: Text(_checking ? '正在检查…' : '检查面板连接'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _checking ? null : _checkNode,
            icon: const Icon(Icons.speed),
            label: const Text('测试当前节点'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              // Construct an allowlisted summary; never copy raw logs, URLs or node data.
              await Clipboard.setData(
                ClipboardData(
                  text: [
                    '${AppIdentity.brandName}诊断信息',
                    '版本：${globalState.packageInfo.version}',
                    '系统：${system.isWindows
                        ? 'Windows'
                        : system.isAndroid
                        ? 'Android'
                        : '其他'}',
                    '登录：${metronSession.authenticated ? '已验证' : '未登录'}',
                    '连接：${running ? '已连接' : '未连接'}',
                    '订阅：${hasProfile ? '已加载' : '未加载'}',
                    '接管：$route',
                    '节点检查：${_nodeStatus.startsWith('可用')
                        ? '正常'
                        : _nodeStatus == '尚未检查'
                        ? '未检查'
                        : '异常，请在客户端查看详情'}',
                    '面板检查：${_panelStatus == '连接正常，会话有效'
                        ? '正常'
                        : _panelStatus == '尚未检查'
                        ? '未检查'
                        : '异常，请在客户端查看详情'}',
                  ].join('\n'),
                ),
              );
              globalState.showNotifier('诊断信息已复制，不含账号和订阅地址');
            },
            icon: const Icon(Icons.copy_outlined),
            label: const Text('复制诊断信息'),
          ),
          const SizedBox(height: 20),
          const Text('进一步检查', style: TextStyle(fontWeight: FontWeight.w600)),
          for (final tool in <(String, IconData, Widget)>[
            ('DNS 查询', Icons.dns_outlined, const DnsQueryPage()),
            ('路由追踪', Icons.route_outlined, const RouteTracePage()),
            ('NAT 测试', Icons.hub_outlined, const NatTestPage()),
            ('本地 Ping', Icons.network_ping, const LocalPingPage()),
          ])
            ListTile(
              leading: Icon(tool.$2),
              title: Text(tool.$1),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => BaseNavigator.push(context, tool.$3),
            ),
        ],
      ),
    );
  }
}
