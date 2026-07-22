import 'package:flutter/material.dart';
import '../../shared/widgets/app_icons.dart';

import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_layout.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/bubble_background.dart';
import '../../shared/widgets/pre_login_top_bar.dart';
import '../../shared/widgets/responsive.dart';

/// Shared scaffold for every pre-login screen — same brand frame, same colors,
/// adaptive split layout on desktop. Pass [compact] for popup-style auth
/// (register sheet) with tighter typography and spacing on handheld.
class AuthShell extends StatelessWidget {
  const AuthShell({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    this.footer,
    this.maxCardWidth = 460,
    this.compact = false,
    this.onClose,
    this.embedded = false,
    this.showSignIn = true,
    this.balanceContent = true,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? footer;
  final double maxCardWidth;
  final bool compact;
  final VoidCallback? onClose;

  /// When true, render only the form column (no scaffold). Used inside sheets.
  final bool embedded;

  /// When false, hides the top-right Sign in link (e.g. on the login screen).
  final bool showSignIn;

  /// Vertically centres the form on handheld full-page auth screens.
  final bool balanceContent;

  @override
  Widget build(BuildContext context) {
    if (embedded) return _formColumn(context);

    final tier = ResponsiveBuilder.of(context);
    final surface = AppPalette.scaffoldBg(context);
    return Scaffold(
      backgroundColor: surface,
      body: tier.isDesktop
          ? SafeArea(child: _wideLayout(context))
          : BubbleBackground(
              bubbleCount: 12,
              surfaceColor: surface,
              child: SafeArea(child: _compactLayout(context)),
            ),
    );
  }

  Widget _wideLayout(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PreLoginTopBar(showSignIn: showSignIn),
        Expanded(
          child: Row(
            children: [
              Expanded(flex: 5, child: _BrandPanel()),
              Expanded(
                flex: 6,
                child: SingleChildScrollView(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxCardWidth),
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.huge),
                        child: _formColumn(context),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _compactLayout(BuildContext context) {
    final inset = compact ? AppSpacing.lg : AppSpacing.xl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PreLoginTopBar(showSignIn: showSignIn),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(inset, 0, inset, inset),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: balanceContent ? constraints.maxHeight : 0,
                  ),
                  child: Align(
                    alignment: balanceContent
                        ? Alignment.center
                        : Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxCardWidth),
                      child: _formColumn(context),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _formColumn(BuildContext context) {
    final theme = Theme.of(context);
    final titleStyle = compact
        ? theme.textTheme.headlineLarge
        : theme.textTheme.displaySmall;
    final subtitleStyle = compact
        ? theme.textTheme.bodySmall
        : theme.textTheme.bodyLarge?.copyWith(color: AppPalette.textMuted(context));
    final headerGap = subtitle == null || subtitle!.isEmpty
        ? AppLayout.pageHeaderGap
        : (compact ? AppSpacing.lg : AppSpacing.huge);
    final footerGap = AppLayout.pageFooterGap;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (onClose != null)
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: onClose,
              icon: const Icon(AppIcons.close, size: 22),
            ),
          ),
        Text(title, style: titleStyle),
        if (subtitle != null && subtitle!.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(subtitle!, style: subtitleStyle),
        ],
        SizedBox(height: headerGap),
        child,
        if (footer != null) ...[
          SizedBox(height: footerGap),
          footer!,
        ],
      ],
    );
  }
}

class _BrandPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4F46E5), Color(0xFF7C3AED), Color(0xFFEC4899)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -80,
            right: -60,
            child: _bubble(220, Colors.white.withOpacity(0.10)),
          ),
          Positioned(
            bottom: -100,
            left: -40,
            child: _bubble(280, Colors.white.withOpacity(0.08)),
          ),
          Positioned(
            top: 180,
            left: 60,
            child: _bubble(80, Colors.white.withOpacity(0.18)),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.huge),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Spacer(),
                Text(
                  'Care that\nnever sleeps.',
                  style: Theme.of(context).textTheme.displayMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        height: 1.05,
                      ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Track vitals from anywhere. Catch deterioration early.\n'
                  'Stay connected with your care team — 24/7.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 16,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: AppSpacing.huge),
                const _StatRow(),
                const SizedBox(height: AppSpacing.huge),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bubble(double size, Color color) {
    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.huge,
      runSpacing: AppSpacing.lg,
      children: const [
        _Stat(value: '24/7', label: 'Monitoring'),
        _Stat(value: '7', label: 'Vital types'),
        _Stat(value: '<2 min', label: 'Alert time'),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            )),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 12,
              letterSpacing: 0.4,
            )),
      ],
    );
  }
}
