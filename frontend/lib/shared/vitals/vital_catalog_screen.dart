import 'package:flutter/material.dart';

import 'admin_vital_catalog_form.dart';
import 'doctor_vital_threshold_form.dart';
import '../../shared/auth/auth_state.dart';
import '../../shared/constants/route_names.dart';
import '../../shared/models/vital.dart';
import '../../shared/navigation/role_nav_destination.dart';
import '../../shared/navigation/staff_destinations.dart';
import '../../shared/state/staff_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_dialog.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/glass_sheet.dart';
import '../../shared/widgets/role_shell.dart';

/// Which staff role is viewing the catalog — controls nav shell and edit flows.
enum VitalCatalogRole { admin, doctor, assistant }

/// Unified vital catalog screen — used by admin, doctor, and assistant routes.
class VitalCatalogScreen extends StatelessWidget {
  const VitalCatalogScreen({
    super.key,
    this.role = VitalCatalogRole.admin,
    this.currentRoute,
    this.destinations,
    this.profileRoute,
    this.notificationsRoute,
  });

  const VitalCatalogScreen.admin({Key? key})
    : this(key: key, role: VitalCatalogRole.admin);

  const VitalCatalogScreen.doctor({Key? key})
    : this(
        key: key,
        role: VitalCatalogRole.doctor,
        profileRoute: RouteNames.doctorProfile,
        notificationsRoute: RouteNames.doctorNotifications,
      );

  const VitalCatalogScreen.assistant({Key? key})
    : this(
        key: key,
        role: VitalCatalogRole.assistant,
        profileRoute: RouteNames.assistantProfile,
        notificationsRoute: RouteNames.assistantNotifications,
      );

  final VitalCatalogRole role;
  final String? currentRoute;
  final List<RoleNavDestination>? destinations;
  final String? profileRoute;
  final String? notificationsRoute;

  bool get _isDoctor => role == VitalCatalogRole.doctor;
  bool get _canToggle => !_isDoctor;

  String get _title => _isDoctor ? 'Global vitals' : 'Vital catalog';

  String get _subtitle => _isDoctor
      ? 'Default vitals, thresholds, and alert ranges'
      : 'Global monitoring templates used across all patients';

  Color get _fabColor =>
      _isDoctor ? AppColors.doctorGreen : AppColors.adminPurple;

  String get _resolvedRoute {
    if (currentRoute != null) return currentRoute!;
    return switch (role) {
      VitalCatalogRole.admin => RouteNames.adminVitalCatalog,
      VitalCatalogRole.doctor => RouteNames.doctorVitalTemplate,
      VitalCatalogRole.assistant => RouteNames.assistantVitalCatalog,
    };
  }

  List<RoleNavDestination> get _resolvedDestinations {
    if (destinations != null) return destinations!;
    return switch (role) {
      VitalCatalogRole.admin => StaffDestinations.admin(),
      VitalCatalogRole.doctor => StaffDestinations.doctor(),
      VitalCatalogRole.assistant => StaffDestinations.assistant(),
    };
  }

  @override
  Widget build(BuildContext context) {
    return RoleShell(
      currentRoute: _resolvedRoute,
      destinations: _resolvedDestinations,
      profileRoute: profileRoute ?? RouteNames.adminProfile,
      notificationsRoute: notificationsRoute ?? RouteNames.adminNotifications,
      title: _title,
      subtitle: _subtitle,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _VitalCatalogActions.create(context, role),
        icon: const Icon(AppIcons.add),
        label: const Text('New vital'),
        backgroundColor: _fabColor,
        foregroundColor: Colors.white,
      ),
      body: AnimatedBuilder(
        animation: StaffState.instance,
        builder: (context, _) {
          final entries = StaffState.instance.vitalCatalog;
          final active = entries.where((e) => e.enabled).toList();
          final inactive = entries.where((e) => !e.enabled).toList();

          if (entries.isEmpty) {
            return const EmptyStateView(
              icon: AppIcons.vitals,
              title: 'No vitals configured',
              message: 'Tap "New vital" to add the first monitoring template.',
            );
          }

          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              if (active.isNotEmpty) ...[
                _SectionHeader(
                  title: 'Active (${active.length})',
                  icon: AppIcons.check,
                  color: AppColors.success,
                ),
                for (final e in active) ...[
                  _CatalogEntryCard(
                    entry: e,
                    role: role,
                    onEdit: () => _VitalCatalogActions.edit(context, e, role),
                    onToggle: _canToggle
                        ? () => _VitalCatalogActions.toggle(context, e, false)
                        : null,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                ],
              ],
              if (inactive.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                _SectionHeader(
                  title: 'Disabled (${inactive.length})',
                  icon: AppIcons.visibilityOff,
                  color: AppPalette.textMuted(context),
                ),
                for (final e in inactive) ...[
                  _CatalogEntryCard(
                    entry: e,
                    role: role,
                    muted: true,
                    onEdit: _isDoctor
                        ? () => _VitalCatalogActions.enable(context, e)
                        : () => _VitalCatalogActions.edit(context, e, role),
                    onToggle: _canToggle
                        ? () => _VitalCatalogActions.toggle(context, e, true)
                        : null,
                    actionLabel: _isDoctor ? 'Enable' : null,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                ],
              ],
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Create / edit / enable flows (role-aware)
// ---------------------------------------------------------------------------

class _VitalCatalogActions {
  _VitalCatalogActions._();

  static String _actorName() {
    final u = AuthState.instance.user;
    return u != null ? '${u.firstName} ${u.lastName}'.trim() : 'Staff';
  }

  static Future<void> create(
    BuildContext context,
    VitalCatalogRole role,
  ) async {
    final result = await GlassSheet.show<VitalCatalogFormResult>(
      context,
      title: 'New vital',
      subtitle: 'Define measurement, thresholds and alerts',
      child: const VitalCatalogForm(),
    );
    if (result == null || result.delete || !context.mounted) return;
    await StaffState.instance.createCatalogEntry(
      label: result.label,
      unit: result.unit,
      normalMin: result.thresholds.normalMin,
      normalMax: result.thresholds.normalMax,
      warningLow: result.thresholds.warningLow,
      warningHigh: result.thresholds.warningHigh,
      criticalLow: result.thresholds.criticalLow,
      criticalHigh: result.thresholds.criticalHigh,
      description: result.description,
      alertConfig: result.alertConfig,
      createdBy: _actorName(),
    );
    if (context.mounted) {
      AppToast.show(context, message: '${result.label} added to catalog.');
    }
  }

  static Future<void> edit(
    BuildContext context,
    VitalCatalogEntry entry,
    VitalCatalogRole role,
  ) async {
    final result = await GlassSheet.show<VitalCatalogFormResult>(
      context,
      title: entry.isCustom
          ? 'Edit · ${entry.displayLabel}'
          : 'Configure · ${entry.displayLabel}',
      subtitle: entry.isCustom
          ? 'Update thresholds, alerts and identity'
          : 'Update global thresholds and alert settings',
      child: VitalCatalogForm(entry: entry),
    );
    if (result == null || !context.mounted) return;

    if (result.delete && entry.isCustom) {
      await StaffState.instance.removeCustomCatalogEntry(entry.id);
      if (context.mounted) {
        AppToast.show(context, message: '${entry.displayLabel} removed.');
      }
      return;
    }

    if (role == VitalCatalogRole.doctor) {
      final confirmed = await AppDialog.confirm(
        context,
        title: 'Update default thresholds?',
        message:
            'This change applies to every assigned patient without a custom override for ${entry.displayLabel}.',
        confirmLabel: 'Update',
        icon: AppIcons.alert,
      );
      if (confirmed != true || !context.mounted) return;
    }

    await StaffState.instance.updateCatalogEntry(
      id: entry.id,
      normalMin: result.thresholds.normalMin,
      normalMax: result.thresholds.normalMax,
      warningLow: result.thresholds.warningLow,
      warningHigh: result.thresholds.warningHigh,
      criticalLow: result.thresholds.criticalLow,
      criticalHigh: result.thresholds.criticalHigh,
      label: entry.isCustom ? result.label : null,
      unit: entry.isCustom ? result.unit : null,
      description: result.description,
      alertConfig: result.alertConfig,
      updatedBy: _actorName(),
    );
    if (context.mounted) {
      AppToast.show(context, message: '${entry.displayLabel} updated.');
    }
  }

  static Future<void> enable(
    BuildContext context,
    VitalCatalogEntry entry,
  ) async {
    if (entry.isCustom) {
      return edit(context, entry, VitalCatalogRole.doctor);
    }
    final result = await GlassSheet.show<VitalThresholdFormResult>(
      context,
      title: 'Enable · ${entry.displayLabel}',
      subtitle: 'Restore global default thresholds',
      child: VitalThresholdForm(
        vital: entry.vital,
        unit: entry.displayUnit,
        initial: entry.toRange(),
        existingOverride: false,
        allowClear: false,
      ),
    );
    if (result == null || result.clear || !context.mounted) return;
    await StaffState.instance.updateCatalogEntry(
      id: entry.id,
      normalMin: result.normalMin,
      normalMax: result.normalMax,
      warningLow: result.warningLow,
      warningHigh: result.warningHigh,
      criticalLow: result.criticalLow,
      criticalHigh: result.criticalHigh,
      enabled: true,
      updatedBy: _actorName(),
    );
    if (!context.mounted) return;
    AppToast.show(context, message: '${entry.displayLabel} vital enabled.');
  }

  static Future<void> toggle(
    BuildContext context,
    VitalCatalogEntry entry,
    bool enabled,
  ) async {
    await StaffState.instance.toggleVitalCatalog(entry.id, enabled);
    if (!context.mounted) return;
    AppToast.show(
      context,
      message: enabled
          ? '${entry.displayLabel} enabled.'
          : '${entry.displayLabel} disabled.',
    );
  }
}

// ---------------------------------------------------------------------------
// Section header
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.icon,
    required this.color,
  });

  final String title;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.xs,
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            title,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Catalog entry card
// ---------------------------------------------------------------------------

class _CatalogEntryCard extends StatelessWidget {
  const _CatalogEntryCard({
    required this.entry,
    required this.role,
    required this.onEdit,
    this.onToggle,
    this.muted = false,
    this.actionLabel,
  });

  final VitalCatalogEntry entry;
  final VitalCatalogRole role;
  final VoidCallback onEdit;
  final VoidCallback? onToggle;
  final bool muted;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = entry.vital?.accent ?? AppColors.brandIndigo;
    final icon = entry.vital?.icon ?? AppIcons.vitals;
    final effectiveAccent = muted ? accent.withValues(alpha: 0.4) : accent;

    return GlassCard(
      frosted: true,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Container(
            height: 40,
            width: 40,
            decoration: BoxDecoration(
              color: effectiveAccent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: effectiveAccent, size: 18),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      entry.displayLabel,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: muted ? AppPalette.textMuted(context) : null,
                      ),
                    ),
                    if (entry.isCustom) ...[
                      const SizedBox(width: 6),
                      _Badge(label: 'Custom', color: AppColors.brandIndigo),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Normal ${_fmt(entry.normalMin, entry)}–${_fmt(entry.normalMax, entry)} ${entry.displayUnit}'
                  ' · Critical <${_fmt(entry.criticalLow, entry)} or >${_fmt(entry.criticalHigh, entry)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppPalette.textMuted(context),
                    fontSize: 10,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                _AlertBadgeRow(entry: entry),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Column(
            children: [
              if (actionLabel != null)
                AppButton(
                  label: actionLabel!,
                  variant: AppButtonVariant.secondary,
                  onPressed: onEdit,
                )
              else
                AppButton.icon(icon: AppIcons.edit, onPressed: onEdit),
              if (onToggle != null) ...[
                const SizedBox(height: 4),
                Switch(
                  value: entry.enabled,
                  onChanged: (_) => onToggle!(),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _fmt(double v, VitalCatalogEntry e) {
    if (e.vital == null) return v.toStringAsFixed(0);
    if (e.vital == VitalKey.temperature || e.vital == VitalKey.weight) {
      return v.toStringAsFixed(1);
    }
    return v.toStringAsFixed(0);
  }
}

class _AlertBadgeRow extends StatelessWidget {
  const _AlertBadgeRow({required this.entry});
  final VitalCatalogEntry entry;

  @override
  Widget build(BuildContext context) {
    final ac = entry.alertConfig;
    return Wrap(
      spacing: 4,
      runSpacing: 2,
      children: [
        if (ac.enableCriticalAlerts)
          _Badge(label: 'Critical alerts', color: AppColors.critical),
        if (ac.enableWarningAlerts)
          _Badge(label: 'Warning alerts', color: AppColors.warning),
        if (ac.escalationEnabled)
          _Badge(
            label: 'Escalates ${ac.escalationDelayMinutes}m',
            color: AppColors.info,
          ),
        if (!ac.enableCriticalAlerts && !ac.enableWarningAlerts)
          _Badge(label: 'Alerts off', color: AppPalette.textMuted(context)),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
