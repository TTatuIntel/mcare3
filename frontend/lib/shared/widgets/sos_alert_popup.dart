import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/web/web_platform.dart' as web_platform;
import '../models/user_role.dart';
import '../navigation/sos_navigation.dart';
import '../services/sos_ring_service.dart';
import '../state/staff_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'app_button.dart';
import 'app_icons.dart';

/// Full-screen SOS alert with looping ringtone. Fires when a new active
/// SOS lands in the doctor/admin caseload.
class SosAlertPopup {
  static final Set<String> _shownIds = {};
  static bool _isOpen = false;

  static void reset() {
    _shownIds.clear();
    _isOpen = false;
    SosRingService.instance.stop();
  }

  static void maybeShow(
    BuildContext context, {
    required Set<String> scopePatientIds,
    UserRole routeFor = UserRole.doctor,
  }) {
    if (_isOpen || !context.mounted) return;

    final fresh = StaffState.instance.patientSos
        .where((e) =>
            e.isActive &&
            e.status == 'active' &&
            scopePatientIds.contains(e.patientId) &&
            !_shownIds.contains(e.id))
        .toList()
      ..sort((a, b) => b.triggeredAt.compareTo(a.triggeredAt));

    if (fresh.isEmpty) return;
    for (final e in fresh) {
      _shownIds.add(e.id);
    }
    _isOpen = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) {
        _isOpen = false;
        return;
      }
      SosRingService.instance.start();
      showGeneralDialog(
        context: context,
        barrierLabel: 'SOS emergency',
        barrierDismissible: false,
        barrierColor: Colors.black.withOpacity(0.72),
        transitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (ctx, _, __) => _SosAlertDialog(
          events: fresh,
          routeFor: routeFor,
        ),
        transitionBuilder: (_, anim, __, child) {
          final curved =
              CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
          return FadeTransition(
            opacity: anim,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.9, end: 1).animate(curved),
              child: child,
            ),
          );
        },
      ).whenComplete(() {
        SosRingService.instance.stop();
        _isOpen = false;
      });
    });
  }
}

class _SosAlertDialog extends StatelessWidget {
  const _SosAlertDialog({
    required this.events,
    required this.routeFor,
  });

  final List<StaffPatientSos> events;
  final UserRole routeFor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lead = events.first;
    final patient =
        StaffState.instance.patientById(lead.patientId);
    final patientName = lead.patientName ?? patient?.name ?? 'Patient';
    final extras = events.skip(1).toList();

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
                border: Border.all(color: AppColors.critical, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.critical.withOpacity(0.45),
                    blurRadius: 32,
                    spreadRadius: 2,
                    offset: const Offset(0, 14),
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
                      _PulsingSosIcon(),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'EMERGENCY SOS',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: AppColors.critical,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.4,
                              ),
                            ),
                            Text(
                              'Patient needs immediate help',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppPalette.textMuted(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    patientName,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: AppPalette.ink(context),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(AppIcons.sos, size: 18, color: AppColors.critical),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          lead.kindLabel,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: AppColors.critical,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (lead.note != null && lead.note!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      lead.note!,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    'Triggered ${DateFormat.jm().format(lead.triggeredAt)} · ${_relative(lead.triggeredAt)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppPalette.textMuted(context),
                    ),
                  ),
                  if (lead.locationLabel != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(AppIcons.location,
                            size: 14, color: AppColors.info),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            lead.locationLabel!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.info,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (extras.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.md),
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: AppPalette.criticalSoft(context),
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusMd),
                      ),
                      child: Text(
                        '+${extras.length} more active SOS',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.critical,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  AppButton(
                    label: 'Respond now',
                    variant: AppButtonVariant.danger,
                    icon: AppIcons.sos,
                    expand: true,
                    onPressed: () => _respond(context, lead, acknowledge: false),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      if (lead.mapsUrl != null)
                        Expanded(
                          child: AppButton(
                            label: 'Open map',
                            variant: AppButtonVariant.secondary,
                            icon: AppIcons.map,
                            onPressed: () => _openMap(lead.mapsUrl!),
                          ),
                        ),
                      if (lead.mapsUrl != null)
                        const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: AppButton(
                          label: 'Acknowledge',
                          variant: AppButtonVariant.secondary,
                          onPressed: () =>
                              _respond(context, lead, acknowledge: true),
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

  static String _relative(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }

  Future<void> _respond(
    BuildContext context,
    StaffPatientSos event, {
    required bool acknowledge,
  }) async {
    SosRingService.instance.stop();
    final resolve = routeFor == UserRole.admin ||
            routeFor == UserRole.mcareAssistant
        ? (String status) =>
            StaffState.instance.adminResolveSos(event.id, status: status)
        : (String status) =>
            StaffState.instance.resolveSos(event.id, status: status);

    if (acknowledge) {
      await resolve('acknowledged');
      if (context.mounted) Navigator.of(context).pop();
      return;
    }

    if (context.mounted) Navigator.of(context).pop();
    SosNavigation.openRespond(
      context,
      patientId: event.patientId,
      eventId: event.id,
      role: routeFor,
    );
    await resolve('acknowledged');
  }

  Future<void> _openMap(String url) async {
    if (kIsWeb) {
      web_platform.openWindow(url, '_blank');
    }
  }
}

class _PulsingSosIcon extends StatefulWidget {
  @override
  State<_PulsingSosIcon> createState() => _PulsingSosIconState();
}

class _PulsingSosIconState extends State<_PulsingSosIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
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
          height: 48,
          width: 48,
          decoration: BoxDecoration(
            color: AppColors.critical.withOpacity(0.12 + 0.08 * _c.value),
            shape: BoxShape.circle,
            border: Border.all(
              color: AppColors.critical.withOpacity(0.5 + 0.4 * _c.value),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.critical
                    .withOpacity(0.25 + 0.35 * _c.value),
                blurRadius: 12 + 10 * _c.value,
                spreadRadius: 1 + 3 * _c.value,
              ),
            ],
          ),
          child: const Icon(AppIcons.sos, color: AppColors.critical, size: 24),
        );
      },
    );
  }
}
