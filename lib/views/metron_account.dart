import 'dart:async';

import 'package:bett_box/common/common.dart';
import 'package:bett_box/common/metron_account.dart';
import 'package:bett_box/common/metron_session.dart';
import 'package:bett_box/enum/enum.dart';
import 'package:bett_box/providers/providers.dart';
import 'package:bett_box/state.dart';
import 'package:bett_box/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'metron_preferences.dart';
import 'metron_about.dart';

String _bytes(int? bytes) {
  if (bytes == null) return '暂未提供';
  const labels = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
  var value = bytes.toDouble();
  var index = 0;
  while (value >= 1024 && index < labels.length - 1) {
    value /= 1024;
    index++;
  }
  return '${value.toStringAsFixed(index == 0 ? 0 : 2)} ${labels[index]}';
}

class MetronAccountView extends ConsumerStatefulWidget {
  const MetronAccountView({super.key});
  @override
  ConsumerState<MetronAccountView> createState() => _MetronAccountViewState();
}

class _MetronAccountViewState extends ConsumerState<MetronAccountView> {
  bool _busy = false;
  String? _message;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual(currentPageLabelProvider, (_, next) {
      if (next == PageLabel.account) unawaited(_refreshAutomatically());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_refreshAutomatically());
    });
  }

  Future<void> _refreshAutomatically() async {
    if (_busy ||
        !mounted ||
        ref.read(currentPageLabelProvider) != PageLabel.account ||
        !metronSession.authenticated) {
      return;
    }
    final generation = metronSession.generation;
    try {
      await metronSession.refreshAccount(ifStale: true);
    } on Object catch (error) {
      if (mounted &&
          generation == metronSession.generation &&
          ref.read(currentPageLabelProvider) == PageLabel.account) {
        setState(() {
          _failed = true;
          _message = '${metronFailure(error, '刷新账号信息').message}；已保留上次资料';
        });
      }
    }
  }

  Future<void> _run(Future<void> Function() action, {String? success}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
      _failed = false;
    });
    try {
      await action();
      if (mounted) setState(() => _message = success);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _message = metronFailure(error, '操作').message;
          _failed = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _date(DateTime? value) => value == null
      ? '暂未提供'
      : DateFormat('yyyy-MM-dd HH:mm').format(value.toLocal());

  String _membershipTime(MetronAccount? account) {
    if (account == null) return '暂未提供';
    if (account.level != null && account.level! < 0) return '尚未开通';
    if (account.level == 0) return '已到期';
    if (account.membershipUnlimited) return '长期有效';
    final expiry = account.membershipExpiresAt;
    if (expiry == null) return '暂未提供';
    final remaining = expiry.difference(DateTime.now());
    if (remaining <= Duration.zero) return '已到期';
    if (remaining.inHours == 0) return '不足 1 小时';
    return '${remaining.inDays} 天 ${remaining.inHours.remainder(24)} 小时';
  }

  Widget _membershipCard(BuildContext context, MetronAccount? account) {
    final level = account?.levelName == null
        ? account?.level == null
              ? '暂未提供'
              : '等级 ${account!.level}'
        : '${account!.levelName}（等级 ${account.level ?? '未知'}）';
    return _AccountCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionTitle(
            icon: Icons.workspace_premium_outlined,
            title: '会员权益',
          ),
          const SizedBox(height: 24),
          Text('会员剩余时长', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          Text(
            _membershipTime(account),
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 20),
          _InfoLine(label: '会员等级', value: level),
          const SizedBox(height: 12),
          _InfoLine(
            label: '会员到期时间',
            value:
                account?.membershipUnlimited == true &&
                    (account?.level ?? 0) > 0
                ? '长期有效'
                : _date(account?.membershipExpiresAt),
          ),
          if (account == null) ...[
            const SizedBox(height: 12),
            Text(
              '会员信息暂不可用，可点击右上角刷新。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  Widget _trafficMetrics(MetronAccount traffic, int columns) {
    final values = [
      _TrafficValue(label: '总流量', value: _bytes(traffic.totalBytes)),
      _TrafficValue(label: '已用流量', value: _bytes(traffic.usedBytes)),
      _TrafficValue(label: '上传', value: _bytes(traffic.uploadBytes)),
      _TrafficValue(label: '下载', value: _bytes(traffic.downloadBytes)),
    ];
    return Column(
      children: [
        for (var row = 0; row < values.length; row += columns)
          Padding(
            padding: EdgeInsets.only(top: row == 0 ? 0 : 14),
            child: Row(
              children: [
                for (var column = 0; column < columns; column++) ...[
                  if (column > 0) const SizedBox(width: 12),
                  Expanded(child: values[row + column]),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _trafficCard(
    BuildContext context,
    MetronAccount traffic, {
    required bool fourColumns,
  }) {
    final colors = Theme.of(context).colorScheme;
    final fraction = traffic.usedFraction;
    return _AccountCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionTitle(icon: Icons.data_usage_outlined, title: '流量概览'),
          const SizedBox(height: 24),
          Text('剩余流量', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          Text(
            _bytes(traffic.remainingBytes),
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: colors.primary,
            ),
          ),
          const SizedBox(height: 16),
          if (fraction != null) ...[
            LinearProgressIndicator(
              value: fraction,
              minHeight: 7,
              borderRadius: BorderRadius.circular(8),
              color: fraction >= .9 ? colors.error : colors.primary,
            ),
            const SizedBox(height: 16),
          ],
          _trafficMetrics(traffic, fourColumns ? 4 : 2),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: metronSession,
    builder: (context, _) {
      final profile = ref.watch(currentProfileProvider);
      final account = metronSession.account;
      final colors = Theme.of(context).colorScheme;
      final alerts = account?.alertsAt(DateTime.now()) ?? const <String>[];
      final traffic =
          account ??
          MetronAccount(
            uploadBytes: profile?.subscriptionInfo?.upload,
            downloadBytes: profile?.subscriptionInfo?.download,
            totalBytes: profile?.subscriptionInfo?.total,
          );
      return CommonScaffold(
        title: '账号',
        backgroundColor: colors.surface,
        actions: [
          IconButton(
            tooltip: '刷新账号信息',
            onPressed: _busy
                ? null
                : () => _run(metronSession.refreshAccount, success: '账号信息已刷新'),
            icon: const Icon(Icons.refresh),
          ),
        ],
        body: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: EdgeInsets.all(constraints.maxWidth < 600 ? 16 : 28),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_busy) ...[
                      const LinearProgressIndicator(),
                      const SizedBox(height: 16),
                    ],
                    _AccountCard(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: colors.primaryContainer,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(
                              Icons.person_outline_rounded,
                              color: colors.onPrimaryContainer,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  account?.name ?? '我的账号',
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  metronSession.email,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: colors.onSurfaceVariant,
                                      ),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.verified_user_outlined,
                                      size: 14,
                                      color: colors.primary,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '自动登录已开启',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: colors.primary),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    for (final alert in alerts)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: colors.errorContainer.withValues(alpha: .55),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.info_outline,
                                size: 20,
                                color: colors.error,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  alert,
                                  style: TextStyle(
                                    color: colors.onErrorContainer,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    LayoutBuilder(
                      builder: (context, size) {
                        final member = _membershipCard(context, account);
                        final usage = _trafficCard(
                          context,
                          traffic,
                          fourColumns: size.maxWidth >= 900,
                        );
                        if (size.maxWidth < 700) {
                          return Column(
                            children: [
                              member,
                              const SizedBox(height: 16),
                              usage,
                            ],
                          );
                        }
                        return IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: member),
                              const SizedBox(width: 16),
                              Expanded(child: usage),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                    _AccountCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const _SectionTitle(
                            icon: Icons.subscriptions_outlined,
                            title: '订阅与服务',
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '流量以面板统计为准，更新订阅会保留节点选择与连接状态。',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 18),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              FilledButton.icon(
                                onPressed: _busy
                                    ? null
                                    : () => _run(
                                        () => globalState.appController
                                            .importMetronSubscription(),
                                        success: '订阅已更新，已保留节点选择和连接状态',
                                      ),
                                icon: const Icon(Icons.refresh, size: 18),
                                label: Text(_busy ? '正在处理…' : '更新订阅'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _busy
                                    ? null
                                    : () => globalState.openUrl(
                                        '${MetronSession.panelUrl.replaceAll(RegExp(r"/+$"), "")}/user/shop',
                                      ),
                                icon: const Icon(
                                  Icons.shopping_bag_outlined,
                                  size: 18,
                                ),
                                label: const Text('套餐与续费'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _busy
                                    ? null
                                    : () => BaseNavigator.push(
                                        context,
                                        const MetronPreferencesView(),
                                      ),
                                icon: const Icon(Icons.tune, size: 18),
                                label: const Text('偏好设置'),
                              ),
                            ],
                          ),
                          if (_message != null) ...[
                            const SizedBox(height: 16),
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                _message!,
                                style: TextStyle(
                                  color: _failed
                                      ? colors.error
                                      : colors.primary,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _AccountCard(
                      padding: EdgeInsets.zero,
                      child: ListTile(
                        leading: const Icon(Icons.info_outline_rounded),
                        title: const Text('关于软件'),
                        subtitle: const Text('基于 Bettbox · 开源与版权'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => BaseNavigator.push(
                          context,
                          const MetronAboutView(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: colors.error,
                        ),
                        onPressed: _busy
                            ? null
                            : () => _run(() async {
                                await Future.wait([
                                  metronSession.logout(),
                                  globalState.appController.updateStatus(false),
                                ]);
                              }),
                        icon: const Icon(Icons.logout, size: 18),
                        label: const Text('退出登录'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.child,
    this.padding = const EdgeInsets.all(22),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    margin: EdgeInsets.zero,
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: BorderSide(
        color: Theme.of(
          context,
        ).colorScheme.outlineVariant.withValues(alpha: .45),
      ),
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.title});
  final IconData icon;
  final String title;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 10),
      Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
    ],
  );
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        flex: 2,
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        flex: 3,
        child: Text(
          value,
          textAlign: TextAlign.right,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    ],
  );
}

class _TrafficValue extends StatelessWidget {
  const _TrafficValue({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 4),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
    ],
  );
}
