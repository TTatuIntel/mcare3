import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/api/admin_api.dart';
import '../../core/realtime/session_poller.dart';
import '../../shared/constants/route_names.dart';
import '../../shared/navigation/staff_destinations.dart';
import '../../shared/state/staff_state.dart';
import '../../shared/utils/file_download.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_dialog.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/glass_sheet.dart';
import '../../shared/widgets/responsive.dart';
import '../../shared/widgets/role_shell.dart';
import '../../shared/widgets/staff_blocks.dart';

class AdminApprovalsView extends StatelessWidget {
  const AdminApprovalsView({super.key});

  @override
  Widget build(BuildContext context) {
    return _ApprovalsScreen(
      currentRoute: RouteNames.adminApprovals,
      destinations: StaffDestinations.admin(),
      profileRoute: RouteNames.adminProfile,
      notificationsRoute: RouteNames.adminNotifications,
    );
  }
}

class _ApprovalsScreen extends StatefulWidget {
  const _ApprovalsScreen({
    required this.currentRoute,
    required this.destinations,
    required this.profileRoute,
    required this.notificationsRoute,
  });

  final String currentRoute;
  final List<dynamic> destinations;
  final String profileRoute;
  final String notificationsRoute;

  @override
  State<_ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends State<_ApprovalsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) SessionPoller.instance.triggerNow();
    });
  }

  Future<void> _uploadCredential(BuildContext context, HealthworkerApproval a) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'doc', 'docx'],
      withData: true,
    );
    final file = result?.files.single;
    if (file == null || !context.mounted) return;
    try {
      final raw = await AdminApi.instance.uploadApprovalCredential(a.id, file: file);
      if (!context.mounted) return;
      if (raw != null) {
        StaffState.instance.patchApprovalFromApi(raw);
        AppToast.success(context, 'Credential document uploaded.');
      } else {
        AppToast.warn(context, 'Upload did not return updated application.');
      }
    } catch (e) {
      if (!context.mounted) return;
      AppToast.error(context, 'Could not upload credential: $e');
    }
  }

  Future<void> _viewCredential(BuildContext context, HealthworkerApproval a) async {
    try {
      final bytes = await AdminApi.instance.fetchApprovalCredentialBytes(a.id);
      if (!context.mounted) return;
      final ext = _extensionFromName(a.credentialDocumentName);
      final saved = await saveBytesAsFile(
        bytes: bytes,
        suggestedName: a.credentialDocumentName ?? 'credential.$ext',
        allowedExtensions: [ext],
      );
      if (!context.mounted) return;
      if (saved) {
        AppToast.success(context, 'Credential document saved.');
      }
    } catch (e) {
      if (!context.mounted) return;
      AppToast.error(context, 'Could not download credential: $e');
    }
  }

  static String _extensionFromName(String? name) {
    if (name == null || !name.contains('.')) return 'pdf';
    return name.split('.').last.toLowerCase();
  }

  HealthworkerApproval? _approvalById(String id) {
    for (final a in StaffState.instance.approvals) {
      if (a.id == id) return a;
    }
    return null;
  }

  Future<void> _showDetail(BuildContext context, HealthworkerApproval a) {
    return GlassSheet.show(
      context,
      title: a.name,
      subtitle: a.specialty,
      child: AnimatedBuilder(
        animation: StaffState.instance,
        builder: (context, _) {
          final current = _approvalById(a.id) ?? a;
          return Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl, AppSpacing.md, AppSpacing.xl, AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _detail('License', current.licenseNumber ?? '—'),
                _detail(
                  'Credential document',
                  current.hasCredentialDocument
                      ? (current.credentialDocumentName ?? 'On file')
                      : 'Not uploaded',
                ),
                _detail('Applied', DateFormat.yMMMd().format(current.appliedAt)),
                _detail('Status', current.status.toUpperCase()),
                const SizedBox(height: AppSpacing.sm),
                if (current.hasCredentialDocument)
                  AppButton(
                    label: 'Download credential',
                    icon: AppIcons.download,
                    variant: AppButtonVariant.secondary,
                    expand: true,
                    onPressed: () => _viewCredential(context, current),
                  ),
                if (current.status == 'pending') ...[
                  const SizedBox(height: AppSpacing.sm),
                  AppButton(
                    label: current.hasCredentialDocument
                        ? 'Replace credential'
                        : 'Upload credential',
                    icon: AppIcons.upload,
                    variant: AppButtonVariant.secondary,
                    expand: true,
                    onPressed: () => _uploadCredential(context, current),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AppButton(
                label: 'Approve',
                icon: AppIcons.check,
                expand: true,
                onPressed: () async {
                  Navigator.of(context).pop();
                  final ok = await AppDialog.confirm(
                    context,
                    title: 'Approve clinician?',
                    message: '${a.name} will gain access to mCare.',
                    icon: AppIcons.approval,
                  );
                  if (ok != true || !context.mounted) return;
                  try {
                    await StaffState.instance.approveApplicationRemote(a.id);
                    if (!context.mounted) return;
                    AppToast.success(context, '${a.name} approved.');
                  } catch (e) {
                    if (!context.mounted) return;
                    AppToast.warn(context, 'Could not approve: $e');
                  }
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              AppButton(
                label: 'Request more info',
                icon: AppIcons.chat,
                variant: AppButtonVariant.secondary,
                expand: true,
                onPressed: () async {
                  Navigator.of(context).pop();
                  await _requestInfo(context, a);
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              AppButton(
                label: 'Reject',
                icon: AppIcons.close,
                variant: AppButtonVariant.danger,
                expand: true,
                onPressed: () async {
                  Navigator.of(context).pop();
                  final ok = await AppDialog.confirm(
                    context,
                    title: 'Reject application?',
                    message: 'This cannot be undone.',
                    danger: true,
                    icon: AppIcons.close,
                  );
                  if (ok != true || !context.mounted) return;
                  try {
                    await StaffState.instance.rejectApplicationRemote(a.id,
                        reason: 'Application rejected by staff.');
                    if (!context.mounted) return;
                    AppToast.info(context, '${a.name} application rejected.');
                  } catch (e) {
                    if (!context.mounted) return;
                    AppToast.warn(context, 'Could not reject: $e');
                  }
                },
              ),
            ],
          ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _requestInfo(BuildContext context, HealthworkerApproval a) async {
    final msgCtrl = TextEditingController();
    final ok = await GlassSheet.show<bool>(
      context,
      title: 'Request more info',
      subtitle: 'Send a message to ${a.name}',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl, AppSpacing.md, AppSpacing.xl, AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(
              controller: msgCtrl,
              label: 'Message',
              hint: 'e.g. Please upload a clearer copy of your license.',
              maxLines: 4,
            ),
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              label: 'Send request',
              icon: AppIcons.chat,
              expand: true,
              onPressed: () {
                if (msgCtrl.text.trim().isEmpty) {
                  AppToast.warn(context, 'Message cannot be empty.');
                  return;
                }
                Navigator.of(context).pop(true);
              },
            ),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await AdminApi.instance
          .requestApplicationInfo(a.id, message: msgCtrl.text.trim());
      if (!context.mounted) return;
      AppToast.success(context, 'Info request sent to ${a.name}.');
    } catch (e) {
      if (!context.mounted) return;
      AppToast.warn(context, 'Could not send request: $e');
    }
  }

  Widget _detail(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Row(
          children: [
            Text('$label: ',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(value),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return RoleShell(
      currentRoute: widget.currentRoute,
      destinations: widget.destinations.cast(),
      profileRoute: widget.profileRoute,
      notificationsRoute: widget.notificationsRoute,
      title: 'Healthworker approvals',
      subtitle: 'Verify license, approve or reject new clinicians',
      body: AnimatedBuilder(
        animation: StaffState.instance,
        builder: (context, _) {
          final pending = StaffState.instance.approvals
              .where((a) => a.status == 'pending')
              .toList();
          final decided = StaffState.instance.approvals
              .where((a) => a.status != 'pending')
              .toList();
          if (pending.isEmpty && decided.isEmpty) {
            return GlassCard(
              frosted: true,
              child: EmptyStateView(
                icon: AppIcons.approval,
                title: 'No applications',
                compact: true,
              ),
            );
          }
          final handheld = ResponsiveBuilder.of(context).isHandheld;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (pending.isNotEmpty)
                StaffListCard(
                  title: 'Pending',
                  children: pending
                      .map((a) => StaffListRow(
                            icon: AppIcons.approval,
                            iconColor: AppColors.warning,
                            title: a.name,
                            subtitle:
                                '${a.specialty}${a.licenseNumber != null ? ' · ${a.licenseNumber}' : ''} · ${DateFormat.MMMd().format(a.appliedAt)}',
                            pill: handheld ? 'Review' : null,
                            pillColor: AppColors.warning,
                            onTap: () => _showDetail(context, a),
                            trailing: handheld
                                ? null
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      AppButton(
                                        label: 'Approve',
                                        size: AppButtonSize.sm,
                                        onPressed: () async {
                                          final ok = await AppDialog.confirm(
                                            context,
                                            title: 'Approve clinician?',
                                            message:
                                                '${a.name} will gain access to mCare.',
                                            icon: AppIcons.approval,
                                          );
                                          if (ok != true) return;
                                          try {
                                            await StaffState.instance
                                                .approveApplicationRemote(a.id);
                                          } catch (e) {
                                            if (!context.mounted) return;
                                            AppToast.warn(
                                                context, 'Could not approve: $e');
                                            return;
                                          }
                                          if (!context.mounted) return;
                                          AppToast.success(
                                              context, '${a.name} approved.');
                                        },
                                      ),
                                      const SizedBox(width: 6),
                                      AppButton(
                                        label: 'Reject',
                                        size: AppButtonSize.sm,
                                        variant: AppButtonVariant.danger,
                                        onPressed: () async {
                                          final ok = await AppDialog.confirm(
                                            context,
                                            title: 'Reject application?',
                                            message: 'This cannot be undone.',
                                            danger: true,
                                            icon: AppIcons.close,
                                          );
                                          if (ok != true) return;
                                          try {
                                            await StaffState.instance
                                                .rejectApplicationRemote(a.id,
                                                    reason:
                                                        'Application rejected by staff.');
                                          } catch (e) {
                                            if (!context.mounted) return;
                                            AppToast.warn(
                                                context, 'Could not reject: $e');
                                            return;
                                          }
                                          if (!context.mounted) return;
                                          AppToast.info(context,
                                              '${a.name} application rejected.');
                                        },
                                      ),
                                    ],
                                  ),
                          ))
                      .toList(),
                ),
              if (decided.isNotEmpty) ...[
                const SizedBox(height: 16),
                StaffListCard(
                  title: 'Decided',
                  children: decided
                      .map((a) => StaffListRow(
                            icon: a.status == 'approved'
                                ? AppIcons.check
                                : AppIcons.close,
                            iconColor: a.status == 'approved'
                                ? AppColors.success
                                : AppColors.critical,
                            title: a.name,
                            subtitle: a.specialty,
                            pill: a.status.toUpperCase(),
                            pillColor: a.status == 'approved'
                                ? AppColors.success
                                : AppColors.critical,
                            onTap: () => _showDetail(context, a),
                          ))
                      .toList(),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Re-exported so the Assistant module can reuse the exact same approvals UI.
class ApprovalsScreen extends StatelessWidget {
  const ApprovalsScreen({
    super.key,
    required this.currentRoute,
    required this.destinations,
    required this.profileRoute,
    required this.notificationsRoute,
  });
  final String currentRoute;
  final List<dynamic> destinations;
  final String profileRoute;
  final String notificationsRoute;
  @override
  Widget build(BuildContext context) => _ApprovalsScreen(
        currentRoute: currentRoute,
        destinations: destinations,
        profileRoute: profileRoute,
        notificationsRoute: notificationsRoute,
      );
}
