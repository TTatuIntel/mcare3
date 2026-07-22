import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/env/app_env.dart';
import '../../core/realtime/session_poller.dart';
import '../../shared/constants/route_names.dart';
import '../../shared/models/user_role.dart';
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
import '../../shared/widgets/staff_blocks.dart';

class AdminAssignmentsView extends StatelessWidget {
  const AdminAssignmentsView({super.key});

  @override
  Widget build(BuildContext context) {
    return AssignmentsScreen(
      currentRoute: RouteNames.adminAssignments,
      destinations: StaffDestinations.admin(),
      profileRoute: RouteNames.adminProfile,
      notificationsRoute: RouteNames.adminNotifications,
    );
  }
}

class AssignmentsScreen extends StatefulWidget {
  const AssignmentsScreen({
    super.key,
    required this.currentRoute,
    required this.destinations,
    required this.profileRoute,
    required this.notificationsRoute,
  });
  final String currentRoute;
  final List destinations;
  final String profileRoute;
  final String notificationsRoute;

  @override
  State<AssignmentsScreen> createState() => _AssignmentsScreenState();
}

class _AssignmentsScreenState extends State<AssignmentsScreen> {
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) SessionPoller.instance.triggerNow();
    });
  }

  Future<void> _openSheet(BuildContext context) async {
    final patients = StaffState.instance.users
        .where((u) => u.role == UserRole.patient && u.status == 'active')
        .toList();
    final doctors = StaffState.instance.users
        .where((u) => u.role == UserRole.doctor && u.status == 'active')
        .toList();

    DirectoryUser? selectedPatient;
    DirectoryUser? selectedDoctor;
    String selectedRole = 'Primary';

    await GlassSheet.show(
      context,
      title: 'New assignment',
      subtitle: 'Link a patient to a care provider',
      child: StatefulBuilder(
        builder: (ctx, setSt) => Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl, AppSpacing.md, AppSpacing.xl, AppSpacing.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Patient picker
              Text('Patient',
                  style: Theme.of(ctx).textTheme.labelMedium?.copyWith(
                        color: AppPalette.textMuted(context),
                      )),
              const SizedBox(height: 4),
              GlassCard(
                frosted: true,
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md, vertical: 4),
                child: patients.isEmpty
                    ? const Text('No active patients found.')
                    : DropdownButton<DirectoryUser>(
                        value: selectedPatient,
                        hint: const Text('Select patient…'),
                        isExpanded: true,
                        underline: const SizedBox.shrink(),
                        onChanged: (v) => setSt(() => selectedPatient = v),
                        items: patients
                            .map((p) => DropdownMenuItem(
                                  value: p,
                                  child: Text(
                                    '${p.name} · ${p.uniqueId}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ))
                            .toList(),
                      ),
              ),
              const SizedBox(height: AppSpacing.md),

              // Provider picker
              Text('Provider (doctor)',
                  style: Theme.of(ctx).textTheme.labelMedium?.copyWith(
                        color: AppPalette.textMuted(context),
                      )),
              const SizedBox(height: 4),
              GlassCard(
                frosted: true,
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md, vertical: 4),
                child: doctors.isEmpty
                    ? const Text('No active doctors found.')
                    : DropdownButton<DirectoryUser>(
                        value: selectedDoctor,
                        hint: const Text('Select provider…'),
                        isExpanded: true,
                        underline: const SizedBox.shrink(),
                        onChanged: (v) => setSt(() => selectedDoctor = v),
                        items: doctors
                            .map((d) => DropdownMenuItem(
                                  value: d,
                                  child: Text(
                                    'Dr. ${d.name} · ${d.uniqueId}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ))
                            .toList(),
                      ),
              ),
              const SizedBox(height: AppSpacing.md),

              // Role picker
              Text('Assignment role',
                  style: Theme.of(ctx).textTheme.labelMedium?.copyWith(
                        color: AppPalette.textMuted(context),
                      )),
              const SizedBox(height: 4),
              GlassCard(
                frosted: true,
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md, vertical: 4),
                child: DropdownButton<String>(
                  value: selectedRole,
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  onChanged: (v) => setSt(() => selectedRole = v ?? 'Primary'),
                  items: const [
                    DropdownMenuItem(value: 'Primary', child: Text('Primary')),
                    DropdownMenuItem(
                        value: 'Consulting', child: Text('Consulting')),
                    DropdownMenuItem(
                        value: 'Specialist', child: Text('Specialist')),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              AppButton(
                label: 'Create assignment',
                icon: AppIcons.assignments,
                expand: true,
                loading: _creating,
                onPressed: () async {
                  if (selectedPatient == null || selectedDoctor == null) {
                    AppToast.warn(ctx,
                        'Select both a patient and a provider.');
                    return;
                  }
                  setSt(() => _creating = true);
                  try {
                    await StaffState.instance.createAssignmentRemote(
                      patientUserId: selectedPatient!.id,
                      providerId: selectedDoctor!.id,
                      role: selectedRole,
                    );
                    // Only inject a local placeholder when the backend is
                    // disabled — otherwise the remote call is authoritative
                    // and the poller will hydrate the real record.
                    if (!AppEnv.backendEnabled) {
                      StaffState.instance.addAssignment(
                        CareAssignment(
                          id: 'as_${DateTime.now().millisecondsSinceEpoch}',
                          patient: selectedPatient!.name,
                          provider: selectedDoctor!.name,
                          assignedAt: DateTime.now(),
                          role: selectedRole,
                        ),
                      );
                    }
                    if (ctx.mounted) {
                      Navigator.of(ctx).pop();
                      AppToast.success(
                          ctx, 'Assignment created successfully.');
                    }
                  } catch (e) {
                    if (ctx.mounted) {
                      AppToast.error(ctx, 'Could not create assignment: $e');
                    }
                  } finally {
                    if (mounted) setState(() => _creating = false);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RoleShell(
      currentRoute: widget.currentRoute,
      destinations: widget.destinations.cast(),
      profileRoute: widget.profileRoute,
      notificationsRoute: widget.notificationsRoute,
      title: 'Assignments',
      subtitle: 'Patient ↔ provider care relationships',
      headerActions: [
        AppButton(
          label: 'New',
          icon: AppIcons.add,
          size: AppButtonSize.sm,
          onPressed: () => _openSheet(context),
        ),
        const SizedBox(width: 8),
      ],
      body: AnimatedBuilder(
        animation: StaffState.instance,
        builder: (context, _) {
          final items = StaffState.instance.assignments;
          if (items.isEmpty) {
            return GlassCard(
              frosted: true,
              child: EmptyStateView(
                icon: AppIcons.assignments,
                title: 'No assignments yet',
                actionLabel: 'Create assignment',
                onAction: () => _openSheet(context),
                compact: true,
              ),
            );
          }
          return StaffListCard(
            children: items
                .map((a) => StaffListRow(
                      icon: AppIcons.assignments,
                      iconColor: AppColors.brandIndigo,
                      title: '${a.patient} → ${a.provider}',
                      subtitle:
                          '${a.role} · since ${DateFormat.MMMd().format(a.assignedAt)}',
                      trailing: AppButton(
                        label: 'End',
                        size: AppButtonSize.sm,
                        variant: AppButtonVariant.danger,
                        onPressed: () async {
                          final ok = await AppDialog.confirm(
                            context,
                            title: 'End assignment?',
                            message:
                                '${a.provider} will no longer see ${a.patient}.',
                            danger: true,
                            icon: AppIcons.close,
                          );
                          if (ok != true) return;
                          try {
                            await StaffState.instance
                                .removeAssignmentRemote(a.id);
                            if (!context.mounted) return;
                            AppToast.info(context, 'Assignment ended.');
                          } catch (e) {
                            if (!context.mounted) return;
                            AppToast.warn(context, 'Could not end: $e');
                          }
                        },
                      ),
                    ))
                .toList(),
          );
        },
      ),
    );
  }
}
