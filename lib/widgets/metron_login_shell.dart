import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:bett_box/common/identity.dart';

/// Shared layout keeps startup, session restoration and sign-in consistent.
class MetronLoginShell extends StatelessWidget {
  const MetronLoginShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final scheme = theme.colorScheme.copyWith(
      primary: dark ? const Color(0xFF8BDFCE) : const Color(0xFF087F73),
      onPrimary: dark ? const Color(0xFF00382F) : Colors.white,
    );
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(
        color: scheme.outlineVariant.withValues(alpha: .65),
      ),
    );
    return Theme(
      data: theme.copyWith(
        colorScheme: scheme,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: dark ? const Color(0xFF202D2C) : const Color(0xFFF7FAF9),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 19,
          ),
          border: border,
          enabledBorder: border,
          focusedBorder: border.copyWith(
            borderSide: BorderSide(color: scheme.primary, width: 1.6),
          ),
          errorBorder: border.copyWith(
            borderSide: BorderSide(color: scheme.error),
          ),
          focusedErrorBorder: border.copyWith(
            borderSide: BorderSide(color: scheme.error, width: 1.6),
          ),
        ),
      ),
      child: Scaffold(
        body: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: dark
                  ? const [Color(0xFF102421), Color(0xFF151D23)]
                  : const [Color(0xFFE8F4EF), Color(0xFFF4F6F8)],
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 920;
              final padding = wide ? 40.0 : 20.0;
              return SingleChildScrollView(
                padding: EdgeInsets.all(padding),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: math.max(0, constraints.maxHeight - padding * 2),
                  ),
                  child: Center(
                    child: Container(
                      constraints: BoxConstraints(maxWidth: wide ? 1000 : 480),
                      decoration: BoxDecoration(
                        color: dark ? const Color(0xFF182320) : Colors.white,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: dark ? const Color(0xFF30453E) : Colors.white,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: dark ? .15 : .06,
                            ),
                            blurRadius: 50,
                            offset: const Offset(0, 20),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (wide) const Expanded(child: _BrandPanel()),
                            Expanded(
                              child: Padding(
                                padding: EdgeInsets.all(wide ? 44 : 24),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    if (!wide) ...[
                                      const Align(
                                        alignment: Alignment.centerLeft,
                                        child: _BrandMark(),
                                      ),
                                      const SizedBox(height: 28),
                                    ],
                                    child,
                                  ],
                                ),
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
          ),
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFF087F73),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Image.asset(
      'assets/images/app_icon.png',
      width: 40,
      height: 40,
      fit: BoxFit.contain,
      semanticLabel: '应用图标',
    ),
  );
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF103E36), Color(0xFF0B6457)],
      ),
    ),
    child: DefaultTextStyle.merge(
      style: Theme.of(context).textTheme.bodyMedium,
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                _BrandMark(),
                SizedBox(width: 14),
                Text(
                  AppIdentity.brandName,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const Spacer(),
            const SizedBox(height: 32),
            const Center(child: _CloudArtwork()),
            const SizedBox(height: 32),
            const Text(
              '让每一次连接\n都简单一点。',
              style: TextStyle(
                fontSize: 34,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              '登录${AppIdentity.brandName}，自动同步你的订阅。\n选择节点，即可开始连接。',
              style: TextStyle(
                fontSize: 14,
                height: 1.8,
                color: Color(0xFFC2DED6),
              ),
            ),
            const SizedBox(height: 32),
            const Spacer(),
            const Row(
              children: [
                Icon(
                  Icons.cloud_done_outlined,
                  color: Color(0xFF9CD3C4),
                  size: 18,
                ),
                SizedBox(width: 8),
                Text(
                  '你的连接，从这里开始',
                  style: TextStyle(fontSize: 12, color: Color(0xFF9CD3C4)),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _CloudArtwork extends StatelessWidget {
  const _CloudArtwork();

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      width: 190,
      height: 170,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 164,
            height: 164,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFF83CCB6).withValues(alpha: .25),
              ),
            ),
          ),
          Container(
            width: 128,
            height: 128,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF93DDC9).withValues(alpha: .09),
            ),
          ),
          const Icon(Icons.cloud_rounded, size: 104, color: Color(0xFFB6E9D9)),
          const Positioned(right: 10, bottom: 18, child: _BrandMark()),
        ],
      ),
    ),
  );
}
