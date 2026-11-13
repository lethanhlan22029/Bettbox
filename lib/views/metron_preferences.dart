import 'package:bett_box/common/common.dart';
import 'package:bett_box/providers/providers.dart';
import 'package:bett_box/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class MetronPreferencesView extends ConsumerWidget {
  const MetronPreferencesView({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingProvider);
    final theme = ref.watch(themeSettingProvider);
    return CommonScaffold(
      title: '偏好设置',
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const ListTile(
            title: Text('外观', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          for (final item in <(ThemeMode, String)>[
            (ThemeMode.system, '跟随系统'),
            (ThemeMode.light, '浅色'),
            (ThemeMode.dark, '深色'),
          ])
            ListTile(
              title: Text(item.$2),
              trailing: theme.themeMode == item.$1
                  ? const Icon(Icons.check)
                  : null,
              onTap: () => ref
                  .read(themeSettingProvider.notifier)
                  .updateState((s) => s.copyWith(themeMode: item.$1)),
            ),
          const Divider(),
          SwitchListTile(
            title: const Text('启动后自动连接'),
            subtitle: const Text('登录验证和订阅加载完成后连接'),
            value: settings.autoRun,
            onChanged: (v) => ref
                .read(appSettingProvider.notifier)
                .updateState((s) => s.copyWith(autoRun: v)),
          ),
          if (system.isDesktop) ...[
            SwitchListTile(
              title: const Text('开机启动'),
              value: settings.autoLaunch,
              onChanged: (v) => ref
                  .read(appSettingProvider.notifier)
                  .updateState((s) => s.copyWith(autoLaunch: v)),
            ),
            SwitchListTile(
              title: const Text('关闭窗口后最小化到托盘'),
              subtitle: const Text('可从托盘菜单退出软件'),
              value: settings.minimizeOnExit,
              onChanged: (v) => ref
                  .read(appSettingProvider.notifier)
                  .updateState((s) => s.copyWith(minimizeOnExit: v)),
            ),
          ],
        ],
      ),
    );
  }
}
