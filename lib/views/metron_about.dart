import 'package:bett_box/common/common.dart';
import 'package:bett_box/common/client_config.g.dart';
import 'package:bett_box/state.dart';
import 'package:bett_box/widgets/widgets.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

class MetronAboutView extends StatelessWidget {
  const MetronAboutView({super.key});

  static const _version = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: ClientDefaults.version,
  );

  @override
  Widget build(BuildContext context) => CommonScaffold(
    title: '关于软件',
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          AppIdentity.displayName,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text('版本 $_version'),
        const SizedBox(height: 28),
        Text('开源与版权', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        const Text(
          '本客户端基于 Bettbox 修改开发；Bettbox 源自 FlClash，代理内核为 Mihomo。'
          '感谢原作者与所有开源贡献者。',
        ),
        const SizedBox(height: 12),
        const Text(
          '相关开源代码的版权归各自原作者及贡献者所有。'
          'Bettbox 和 Mihomo 使用 GNU GPL v3 许可证；第三方组件遵循各自的许可证。',
        ),
        const SizedBox(height: 16),
        for (final project in const [
          ('Bettbox 原项目', 'https://github.com/appshubcc/Bettbox'),
          ('FlClash 原项目', 'https://github.com/chen08209/FlClash'),
          ('Mihomo 内核', 'https://github.com/MetaCubeX/mihomo'),
        ])
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.code),
            title: Text(project.$1),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => globalState.openUrl(project.$2),
          ),
        const Divider(),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.description_outlined),
          title: const Text('GNU GPL v3 许可证'),
          subtitle: const Text('离线查看许可证全文'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => BaseNavigator.push(context, const MetronLicenseView()),
        ),
      ],
    ),
  );
}

class MetronLicenseView extends StatefulWidget {
  const MetronLicenseView({super.key});

  @override
  State<MetronLicenseView> createState() => _MetronLicenseViewState();
}

class _MetronLicenseViewState extends State<MetronLicenseView> {
  late final Future<String> _text = rootBundle.loadString('LICENSE');

  @override
  Widget build(BuildContext context) => CommonScaffold(
    title: 'GNU GPL v3 许可证',
    body: FutureBuilder<String>(
      future: _text,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('许可证文件暂时无法读取'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: SelectionArea(
            child: Text(
              snapshot.data!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(height: 1.6),
            ),
          ),
        );
      },
    ),
  );
}
