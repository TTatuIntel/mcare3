import 'dart:async';

import 'package:flutter/material.dart';

import 'register_view.dart';
import '../shared/theme/app_colors.dart';
import '../shared/theme/app_spacing.dart';
import '../shared/widgets/app_button.dart';
import '../shared/widgets/app_icons.dart';
import '../shared/widgets/brand_logo.dart';
import '../shared/widgets/bubble_background.dart';
import '../shared/widgets/glass_card.dart';
import '../shared/widgets/pre_login_top_bar.dart';
import '../shared/widgets/responsive.dart';

/// Branded launch splash — same wordmark + ECG animation as the design system.
/// Used during bootstrap and as the intro panel inside [LandingView].
class AppSplashScreen extends StatelessWidget {
  const AppSplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final surface = AppPalette.scaffoldBg(context);
    return Scaffold(
      backgroundColor: surface,
      body: BubbleBackground(
        bubbleCount: 10,
        surfaceColor: surface,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BrandLogo(
                height: BrandLogo.splashHeight,
                tappable: false,
                animateHeartbeat: true,
                showLifeline: true,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Remote care, connected',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppPalette.textMuted(context),
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.4,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pre-login landing: Flutter splash overlay until bootstrap completes, then hero.
class LandingView extends StatefulWidget {
  const LandingView({super.key, this.splashOnly = false});

  /// When true, shows only [AppSplashScreen] (used in tests).
  final bool splashOnly;

  @override
  State<LandingView> createState() => _LandingViewState();
}

class _LandingViewState extends State<LandingView> {
  @override
  Widget build(BuildContext context) {
    if (widget.splashOnly) {
      return const AppSplashScreen();
    }

    final surface = AppPalette.scaffoldBg(context);
    return Scaffold(
      backgroundColor: surface,
      body: BubbleBackground(
        bubbleCount: 14,
        surfaceColor: surface,
        child: SafeArea(
          child: ResponsiveBuilder(
            builder: (context, tier) {
              final horizontal = tier.isDesktop
                  ? 72.0
                  : (tier.isTablet ? AppSpacing.xl : AppSpacing.lg);
              final vertical = tier.isMobile ? AppSpacing.md : AppSpacing.xl;
              const maxContentWidth = 1280.0;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PreLoginTopBar(
                    padding: EdgeInsets.fromLTRB(
                      horizontal,
                      AppSpacing.sm,
                      horizontal,
                      AppSpacing.md,
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints:
                            const BoxConstraints(maxWidth: maxContentWidth),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: horizontal,
                            vertical: vertical,
                          ),
                          child: Column(
                            children: [
                              Expanded(
                                child: Align(
                                  alignment: tier.isMobile
                                      ? const Alignment(0, 0.08)
                                      : const Alignment(0, 0.04),
                                  child: _Hero(tier: tier),
                                ),
                              ),
                              _LandingFooter(tier: tier),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _LandingFooter extends StatelessWidget {
  const _LandingFooter({required this.tier});
  final ScreenTier tier;

  @override
  Widget build(BuildContext context) {
    final isMobile = tier.isMobile;
    final muted = AppPalette.textMuted(context);
    final items = const ['Privacy', 'Terms', 'Support', 'Contact'];

    return Padding(
      padding: EdgeInsets.only(top: isMobile ? AppSpacing.md : AppSpacing.lg),
      child: isMobile
          ? Column(
              children: [
                _trustRow(muted),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '© 2026 mCare · Remote Patient Monitoring',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              ],
            )
          : Row(
              children: [
                Text(
                  '© 2026 mCare',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
                const SizedBox(width: AppSpacing.lg),
                // Flexible so the chips can wrap instead of overflowing on
                // narrow desktop-tier windows (~800 px).
                Flexible(child: _trustRow(muted)),
                const Spacer(),
                ...items.map(
                  (label) => Padding(
                    padding: const EdgeInsets.only(left: AppSpacing.lg),
                    child: Text(
                      label,
                      style: TextStyle(
                        color: muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _trustRow(Color muted) => Wrap(
        spacing: AppSpacing.md,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _trustChip(Icons.lock_rounded, 'HIPAA-aware', muted),
          _trustChip(AppIcons.approval, 'End-to-end secure', muted),
          _trustChip(Icons.bolt_rounded, '<2 min alert time', muted),
        ],
      );

  Widget _trustChip(IconData icon, String label, Color muted) => Builder(
        builder: (context) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: muted),
            const SizedBox(width: 5),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: muted,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      );
}

/// Rotating value-prop content displayed inside the hero.
///
/// Headline + subline + chip label cycle every few seconds with a crossfade,
/// keeping the user on one viewport while surfacing every feature pitch. The
/// CTA below stays fixed — only the marketing copy animates.
class _HeroMessage {
  const _HeroMessage({
    required this.chip,
    required this.headline,
    required this.headlineMobile,
    required this.subline,
    required this.sublineMobile,
  });

  final String chip;
  final String headline;
  final String headlineMobile;
  final String subline;
  final String sublineMobile;
}

const List<_HeroMessage> _messages = [
  _HeroMessage(
    chip: 'Remote Patient Monitoring',
    headline: 'Your vitals.\nTheir attention.',
    headlineMobile: 'Your vitals,\ntheir attention.',
    subline:
        'Track blood pressure, glucose, heart rate and more from home.\n'
            'Critical readings reach your care team in seconds.',
    sublineMobile:
        'Track vitals from home. Critical readings reach your care team in seconds.',
  ),
  _HeroMessage(
    chip: 'Instant Alerts',
    headline: 'Abnormal readings.\nNotified in seconds.',
    headlineMobile: 'Abnormal readings,\nnotified in seconds.',
    subline:
        'Out-of-range vitals page your assigned clinician the moment they\n'
            'happen — no waiting, no missed signals.',
    sublineMobile:
        'Out-of-range vitals page your clinician the moment they happen.',
  ),
  _HeroMessage(
    chip: 'Medication Adherence',
    headline: 'Every dose.\nOn schedule.',
    headlineMobile: 'Every dose,\non schedule.',
    subline:
        'Reminders, refill tracking and proof of dose your care team\n'
            'can see in real time.',
    sublineMobile:
        'Reminders, refills and proof of dose — visible to your care team.',
  ),
  _HeroMessage(
    chip: 'Appointments',
    headline: 'Visits that fit\nyour life.',
    headlineMobile: 'Visits that fit\nyour life.',
    subline:
        'Book in-person, virtual or phone appointments with your\n'
            'providers in one tap.',
    sublineMobile:
        'Book in-person, virtual or phone visits with one tap.',
  ),
  _HeroMessage(
    chip: 'Emergency SOS',
    headline: 'One tap.\nHelp on the way.',
    headlineMobile: 'One tap.\nHelp on the way.',
    subline:
        'Sends your live location and medical summary to your contacts\n'
            'and care team instantly.',
    sublineMobile:
        'Sends your live location and medical summary instantly.',
  ),
];

class _Hero extends StatefulWidget {
  const _Hero({required this.tier});
  final ScreenTier tier;

  @override
  State<_Hero> createState() => _HeroState();
}

class _HeroState extends State<_Hero> {
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      setState(() => _index = (_index + 1) % _messages.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tier = widget.tier;
    final isWide = tier.isDesktop;
    final isMobile = tier.isMobile;
    final headlineFontSize =
        isWide ? 52.0 : (tier.isTablet ? 40.0 : 32.0);
    final descriptionFontSize = isMobile ? 15.0 : 16.5;
    final descriptionStyle = Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: AppPalette.textMuted(context),
          height: 1.5,
          fontSize: descriptionFontSize,
        );
    final heroMaxWidth =
        isWide ? double.infinity : (isMobile ? 360.0 : 520.0);
    final ctaSize = isMobile ? AppButtonSize.md : AppButtonSize.lg;
    final message = _messages[_index];

    final headline = Column(
      crossAxisAlignment:
          isWide ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 450),
          transitionBuilder: _fadeSlide,
          child: Container(
            key: ValueKey('chip-${message.chip}'),
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.brandIndigo.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            ),
            child: Text(
              message.chip,
              style: const TextStyle(
                color: AppColors.brandIndigo,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.35,
              ),
            ),
          ),
        ),
        SizedBox(height: isMobile ? AppSpacing.md : AppSpacing.lg),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 450),
          transitionBuilder: _fadeSlide,
          child: Text(
            isMobile ? message.headlineMobile : message.headline,
            key: ValueKey('headline-${message.headline}'),
            textAlign: isWide ? TextAlign.left : TextAlign.center,
            style: Theme.of(context).textTheme.displayLarge?.copyWith(
                  fontSize: headlineFontSize,
                  height: 1.08,
                  fontWeight: FontWeight.w800,
                  letterSpacing: isMobile ? -0.6 : -0.9,
                ),
          ),
        ),
        SizedBox(height: isMobile ? AppSpacing.md : AppSpacing.lg),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 450),
          transitionBuilder: _fadeSlide,
          child: Text(
            isMobile ? message.sublineMobile : message.subline,
            key: ValueKey('sub-${message.subline}'),
            textAlign: isWide ? TextAlign.left : TextAlign.center,
            style: descriptionStyle,
          ),
        ),
        SizedBox(height: isMobile ? AppSpacing.xl : AppSpacing.xxl),
        SizedBox(
          width: isWide ? null : double.infinity,
          child: AppButton(
            label: 'Get started',
            size: ctaSize,
            trailingIcon: AppIcons.chevronRight,
            expand: !isWide,
            onPressed: () => RegisterView.show(context),
          ),
        ),
        SizedBox(height: isMobile ? AppSpacing.xxl * 1.5 : AppSpacing.xxl * 2),
      ],
    );

    if (!isWide) {
      return Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: heroMaxWidth),
          child: headline,
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: headline),
        const SizedBox(width: 48),
        const Expanded(child: _HeroPreviewCard()),
      ],
    );
  }
}

Widget _fadeSlide(Widget child, Animation<double> animation) {
  final offset = Tween<Offset>(
    begin: const Offset(0, 0.12),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
  return FadeTransition(
    opacity: animation,
    child: SlideTransition(position: offset, child: child),
  );
}

class _HeroPreviewCard extends StatelessWidget {
  const _HeroPreviewCard();

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: AppPalette.isDark(context)
            ? const [AppColors.darkSurface, AppColors.darkSurfaceAlt]
            : const [Color(0xFFFFFFFF), Color(0xFFF8FAFC)],
      ),
      shadow: const [
        BoxShadow(
            color: Color(0x14000000),
            blurRadius: 40,
            offset: Offset(0, 20),
            spreadRadius: -10),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                height: 36,
                width: 36,
                decoration: BoxDecoration(
                  color: AppColors.heartRed.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: const Icon(Icons.favorite,
                    color: AppColors.heartRed, size: 18),
              ),
              const SizedBox(width: AppSpacing.md),
              const Expanded(
                child: Text('Heart rate',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppPalette.successSoft(context),
                  borderRadius:
                      BorderRadius.circular(AppSpacing.radiusPill),
                ),
                child: const Text('Normal',
                    style: TextStyle(
                        color: AppColors.success,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              const Text('72',
                  style: TextStyle(
                      fontSize: 56,
                      fontWeight: FontWeight.w700,
                      color: AppColors.heartRed)),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text('bpm',
                    style: TextStyle(
                        color: AppPalette.textMuted(context), fontSize: 14)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            height: 80,
            child: CustomPaint(painter: _MiniLinePainter()),
          ),
          const SizedBox(height: AppSpacing.lg),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppPalette.infoSoft(context),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: Row(
              children: [
                const Icon(AppIcons.info, size: 16, color: AppColors.info),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Dr. Mensah was notified.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.info,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.heartRed
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final fill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AppColors.heartRed.withValues(alpha: 0.22),
          AppColors.heartRed.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final values = [0.6, 0.4, 0.7, 0.5, 0.55, 0.3, 0.65, 0.45, 0.55, 0.5];
    final step = size.width / (values.length - 1);
    final path = Path()..moveTo(0, size.height * (1 - values.first));
    for (var i = 1; i < values.length; i++) {
      final x = i * step;
      final y = size.height * (1 - values[i]);
      final prevX = (i - 1) * step;
      final prevY = size.height * (1 - values[i - 1]);
      final c1 = Offset(prevX + step / 2, prevY);
      final c2 = Offset(x - step / 2, y);
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, x, y);
    }
    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(fillPath, fill);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
