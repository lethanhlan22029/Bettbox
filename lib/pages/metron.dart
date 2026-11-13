import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bett_box/common/metron_session.dart';
import 'package:bett_box/common/identity.dart';
import 'package:bett_box/providers/providers.dart';
import 'package:bett_box/state.dart';
import 'package:bett_box/enum/enum.dart';
import 'home.dart';
import 'package:bett_box/widgets/metron_login_shell.dart';
import 'package:bett_box/views/metron_about.dart';
import 'package:bett_box/common/common.dart' show BaseNavigator;

class MetronPage extends ConsumerStatefulWidget {
  const MetronPage({super.key});
  @override
  ConsumerState<MetronPage> createState() => _MetronPageState();
}

class _MetronPageState extends ConsumerState<MetronPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;
  bool _showPassword = false;
  String? _loginStatus;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = metronFailure(error, '操作').message;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _loginStatus = null;
        });
      }
    }
  }

  Future<void> _login() async {
    if (_busy || !(_form.currentState?.validate() ?? false)) return;
    await _run(() async {
      var stage = '账号登录';
      setState(() => _loginStatus = '正在验证账号…');
      try {
        await metronSession.login(_email.text, _password.text, _code.text);
        _password.clear();
        _code.clear();
        stage = '同步订阅';
        if (mounted) setState(() => _loginStatus = '正在同步订阅…');
        await globalState.appController.importMetronSubscription();
        stage = '启用登录会话';
        if (mounted) setState(() => _loginStatus = '正在保存登录状态…');
        ref.read(currentPageLabelProvider.notifier).value = PageLabel.dashboard;
        await metronSession.activate();
        await globalState.appController.connectAfterMetronLogin();
      } on Object catch (error) {
        await metronSession.logout();
        throw metronFailure(error, stage);
      }
      // Tray refresh is cosmetic and must never log a valid user out.
      unawaited(
        globalState.appController
            .updateTray(false, false, true)
            .catchError((Object _) {}),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final initialized = ref.watch(initProvider);
    return ListenableBuilder(
      listenable: metronSession,
      builder: (context, _) {
        if (!initialized || metronSession.restoring) {
          return MetronLoginShell(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 24),
                Text(
                  metronSession.restoring
                      ? '正在恢复登录…'
                      : '正在准备${AppIdentity.brandName}…',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(metronSession.restoring ? '正在验证登录状态并同步订阅' : '即将就绪，请稍候'),
              ],
            ),
          );
        }
        if (!metronSession.authenticated) return _buildLogin(context);
        return const HomePage();
      },
    );
  }

  Widget _buildLogin(BuildContext context) {
    final error = _error ?? metronSession.restoreError;
    return MetronLoginShell(
      child: Form(
        key: _form,
        child: AutofillGroup(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '欢迎回来',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '登录${AppIdentity.brandName}',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: -.5,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '登录后，你的订阅将自动同步。',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 32),
              TextFormField(
                controller: _email,
                enabled: !_busy,
                autofillHints: const [AutofillHints.username],
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: '邮箱',
                  hintText: '请输入邮箱地址',
                  prefixIcon: Icon(Icons.mail_outline_rounded, size: 20),
                ),
                validator: (value) =>
                    (value?.trim().isEmpty ?? true) ? '请输入邮箱' : null,
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _password,
                enabled: !_busy,
                obscureText: !_showPassword,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.done,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: '密码',
                  hintText: '请输入登录密码',
                  prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                  suffixIcon: IconButton(
                    tooltip: _showPassword ? '隐藏密码' : '显示密码',
                    onPressed: _busy
                        ? null
                        : () => setState(() => _showPassword = !_showPassword),
                    icon: Icon(
                      _showPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 20,
                    ),
                  ),
                ),
                validator: (value) => (value?.isEmpty ?? true) ? '请输入密码' : null,
                onFieldSubmitted: (_) => unawaited(_login()),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _code,
                enabled: !_busy,
                autofillHints: const [AutofillHints.oneTimeCode],
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: '两步验证码',
                  hintText: '仅开启两步验证时填写',
                  prefixIcon: Icon(Icons.shield_outlined, size: 20),
                ),
                onFieldSubmitted: (_) => unawaited(_login()),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Icon(
                    Icons.check_circle_outline_rounded,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '下次启动自动登录',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              if (error != null) ...[
                const SizedBox(height: 20),
                _LoginError(message: error),
              ],
              const SizedBox(height: 28),
              SizedBox(
                height: 52,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _busy ? null : _login,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_busy) ...[
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Flexible(
                        child: Text(
                          _busy ? (_loginStatus ?? '正在登录…') : '登录',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (!_busy) ...[
                        const SizedBox(width: 10),
                        const Icon(Icons.arrow_forward_rounded, size: 18),
                      ],
                    ],
                  ),
                ),
              ),
              if (metronSession.canRestore) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _run(
                          () =>
                              globalState.appController.restoreMetronSession(),
                        ),
                  child: const Text('重试自动登录'),
                ),
              ],
              const SizedBox(height: 24),
              Text(
                '登录即同步，无需手动导入订阅',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () =>
                    BaseNavigator.push(context, const MetronAboutView()),
                child: const Text('基于 Bettbox · 开源与版权'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoginError extends StatelessWidget {
  const _LoginError({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.errorContainer.withValues(alpha: .45),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline_rounded, color: colors.error, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: colors.error,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
