import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shared/constants/route_names.dart';
import '../../shared/models/vital.dart';
import '../../shared/state/staff_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_icons.dart';
import '../alerts/doctor_alert_resolve_sheet.dart';
import '../patients/doctor_patient_section.dart';

/// Modal that fires when one or more critical alerts land on the doctor's
/// caseload that they haven't seen yet. Tracks which alert ids have been
/// shown so we don't re-prompt for the same event after dismissal.
class CriticalAlertPopup {
  static final Set<String> _shownIds = {};
  static bool _isOpen = false;

  /// Should be called whenever StaffState ticks (e.g. inside an
  /// AnimatedBuilder on the dashboard). It scans for unseen critical
  /// alerts in the doctor's caseload and shows the popup.
  static void maybeShow(BuildContext context) {
    if (_isOpen || !context.mounted) return;
    final assignedIds = StaffState.instance
        .assignedPatientsForDoctor()
        .map((p) => p.id)
        .toSet();
    final fresh = StaffState.instance.alerts
        .where((a) =>
            a.severity == RiskLevel.critical &&
            !a.acknowledged &&
            !a.resolved &&
            assignedIds.contains(a.patientId) &&
            !_shownIds.contains(a.id))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    if (fresh.isEmpty) return;
    for (final a in fresh) {
      _shownIds.add(a.id);
    }
    _isOpen = true;

    // Defer so we never push a route inside a build phase.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) {
        _isOpen = false;
        return;
      }
      showGeneralDialog(
        context: context,
        barrierLabel: 'Critical alert',
        barrierDismissible: true,
        barrierColor: Colors.black.withOpacity(0.55),
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (ctx, _, __) =>
            _CriticalAlertDialog(alerts: fresh),
        transitionBuilder: (_, anim, __, child) {
          final curved =
              CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
          return FadeTransition(
            opacity: anim,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
              child: child,
            ),
          );
        },
      ).whenComplete(() => _isOpen = false);
    });
  }

  /// Forget which alerts have been shown. Use on logout so a fresh
  /// session re-prompts.
  static void reset() {
    _shownIds.clear();
    _isOpen = false;
  }
}

class _CriticalAlertDialog extends StatelessWidget {
  const _CriticalAlertDialog({required this.alerts});

  final List<StaffAlert> alerts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lead = alerts.first;
    final extras = alerts.skip(1).toList();

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Material(
            color: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                color: AppPalette.surface(context),
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                border: Border.all(color: AppColors.critical, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.critical.withOpacity(0.35),
                    blurRadius: 28,
                    spreadRadius: 1,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      _PulsingDot(),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        'CRITICAL VITAL',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppColors.critical,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Dismiss',
                        icon: Icon(AppIcons.close,
                            size: 20, color: AppPalette.textMuted(context)),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    lead.patientName,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(lead.vital.icon,
                          size: 16, color: AppColors.critical),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${lead.vital.label} · ${lead.value}',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: AppColors.critical,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Detected ${DateFormat.jm().format(lead.createdAt)} · ${DateFormat.MMMd().format(lead.createdAt)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppPalette.textMuted(context),
                    ),
                  ),
                  if (extras.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.md),
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: AppPalette.criticalSoft(context),
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusMd),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '+${extras.length} more critical event${extras.length == 1 ? '' : 's'}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.critical,
                            ),
                          ),
                          const SizedBox(height: 4),
                          ...extras.take(3).map(
                                (e) => Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    '• ${e.patientName} · ${e.vital.shortLabel} ${e.value}',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ),
                              ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  AppButton(
                    label: 'Resolve now',
                    icon: AppIcons.check,
                    expand: true,
                    onPressed: () async {
                      Navigator.of(context).pop();
                      await DoctorAlertResolveFlow.resolve(context, lead);
                    },
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: AppButton(
                          label: 'Acknowledge',
                          variant: AppButtonVariant.secondary,
                          onPressed: () async {
                            final ok = await StaffState.instance
                                .acknowledgeAlert(lead.id);
                            if (!context.mounted) return;
                            if (ok) Navigator.of(context).pop();
                          },
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: AppButton(
                          label: 'Open chart',
                          variant: AppButtonVariant.danger,
                          onPressed: () async {
                            await StaffState.instance
                                .acknowledgeAlert(lead.id);
                            if (!context.mounted) return;
                            final nav =
                                Navigator.of(context, rootNavigator: true);
                            if (nav.canPop()) nav.pop();
                            await Future<void>.delayed(Duration.zero);
                            if (!nav.mounted) return;
                            await nav.pushNamed(
                              RouteNames.doctorPatientChart,
                              arguments: {
                                'patientId': lead.patientId,
                                'section': DoctorPatientSection.vitals.name,
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        return Container(
          height: 10,
          width: 10,
          decoration: BoxDecoration(
            color: AppColors.critical,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.critical
                    .withOpacity(0.4 + 0.5 * _c.value),
                blurRadius: 8 + 6 * _c.value,
                spreadRadius: 1 + 2 * _c.value,
              ),
            ],
          ),
        );
      },
    );
  }
}
