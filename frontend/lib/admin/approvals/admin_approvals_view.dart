import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/api/admin_api.dart';
import '../../core/api/staff_mapper.dart';
import '../../core/env/app_env.dart';
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
import '../../shared/widgets/app_loading_view.dart';
import '../../shared/widgets/app_page_route.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/glass_sheet.dart';
import '../../shared/widgets/responsive.dart';
import '../../shared/widgets/role_shell.dart';
import '../../shared/widgets/section_label.dart';
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
  final Set<String> _busyApprovalIds = <String>{};
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      SessionPoller.instance.triggerNow();
      _loadApprovals();
    });
  }

  Future<void> _loadApprovals() async {
    // Demo data is already seeded by the session service. AdminApi returns an
    // empty collection while the backend is disabled, so do not erase it.
    if (!AppEnv.backendEnabled) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await AdminApi.instance.listApprovals();
      final approvals = rows
          .map((row) => StaffMapper.approvalFromApi(row))
          .toList();
      StaffState.instance.mergeApprovals(approvals);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _uploadCredential(
    BuildContext context,
    HealthworkerApproval a,
  ) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'doc', 'docx'],
      withData: true,
    );
    final file = result?.files.single;
    if (file == null || !context.mounted) return;
    try {
      final raw = await AdminApi.instance.uploadApprovalCredential(
        a.id,
        file: file,
      );
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

  Future<void> _viewCredential(
    BuildContext context,
    HealthworkerApproval a,
  ) async {
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

  Future<void> _showDetail(
    BuildContext pageContext,
    HealthworkerApproval approval,
  ) {
    return GlassSheet.show<void>(
      pageContext,
      title: approval.name,
      subtitle: 'Clinician application · ${approval.specialty}',
      child: AnimatedBuilder(
        animation: StaffState.instance,
        builder: (sheetContext, _) {
          final current = _approvalById(approval.id) ?? approval;
          final busy = _busyApprovalIds.contains(current.id);
          return Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.md,
              AppSpacing.xl,
              AppSpacing.xl,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ApprovalIdentityCard(approval: current),
                const SizedBox(height: AppSpacing.lg),
                _ApprovalDetailRow(
                  label: 'License',
                  value: current.licenseNumber ?? 'Not provided',
                ),
                _ApprovalDetailRow(
                  label: 'Credential',
                  value: current.hasCredentialDocument
                      ? (current.credentialDocumentName ?? 'Document on file')
                      : 'Not uploaded',
                ),
                _ApprovalDetailRow(
                  label: 'Applied',
                  value: DateFormat.yMMMd().add_jm().format(current.appliedAt),
                ),
                _ApprovalDetailRow(
                  label: 'Status',
                  value: _statusLabel(current.status),
                  valueColor: _statusColor(current.status),
                ),
                if (current.hasCredentialDocument) ...[
                  const SizedBox(height: AppSpacing.sm),
                  AppButton(
                    label: 'Download credential',
                    icon: AppIcons.download,
                    variant: AppButtonVariant.secondary,
                    expand: true,
                    onPressed: busy
                        ? null
                        : () => _viewCredential(sheetContext, current),
                  ),
                ],
                if (current.status == 'pending') ...[
                  const SizedBox(height: AppSpacing.sm),
                  AppButton(
                    label: current.hasCredentialDocument
                        ? 'Replace credential'
                        : 'Upload credential',
                    icon: AppIcons.upload,
                    variant: AppButtonVariant.secondary,
                    expand: true,
                    onPressed: busy
                        ? null
                        : () => _uploadCredential(sheetContext, current),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AppButton(
                    label: 'Approve clinician',
                    icon: AppIcons.check,
                    expand: true,
                    loading: busy,
                    onPressed: busy
                        ? null
                        : () async {
                            final approved = await _approveApplication(
                              sheetContext,
                              current,
                            );
                            if (approved && sheetContext.mounted) {
                              Navigator.of(
                                sheetContext,
                                rootNavigator: true,
                              ).pop();
                            }
                          },
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AppButton(
                    label: 'Request more information',
                    icon: AppIcons.chat,
                    variant: AppButtonVariant.secondary,
                    expand: true,
                    onPressed: busy
                        ? null
                        : () => _requestInfo(sheetContext, current),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AppButton(
                    label: 'Reject application',
                    icon: AppIcons.close,
                    variant: AppButtonVariant.danger,
                    expand: true,
                    loading: busy,
                    onPressed: busy
                        ? null
                        : () async {
                            final rejected = await _rejectApplication(
                              sheetContext,
                              current,
                            );
                            if (rejected && sheetContext.mounted) {
                              Navigator.of(
                                sheetContext,
                                rootNavigator: true,
                              ).pop();
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

  Future<bool> _approveApplication(
    BuildContext context,
    HealthworkerApproval approval,
  ) async {
    final confirmed = await AppDialog.confirm(
      context,
      title: 'Approve clinician?',
      message:
          '${approval.name} gets clinician access, and a temporary password '
          'is emailed to ${approval.email} straight away. They must choose '
          'their own password the first time they sign in.',
      confirmLabel: 'Approve',
      icon: AppIcons.approval,
    );
    if (confirmed != true || !mounted) return false;

    _setApprovalBusy(approval.id, true);
    try {
      String? outcome;
      if (AppEnv.backendEnabled) {
        outcome = await StaffState.instance.approveApplicationRemote(
          approval.id,
        );
      } else {
        StaffState.instance.setApproval(approval.id, 'approved');
      }
      if (!context.mounted) return true;
      // The server names the inbox it reached, and says so plainly when the
      // email did not leave — an approval nobody was told about is a
      // clinician who cannot sign in.
      AppToast.success(context, outcome ?? '${approval.name} approved.');
      return true;
    } catch (error) {
      if (context.mounted) {
        AppToast.error(context, 'Could not approve application: $error');
      }
      return false;
    } finally {
      _setApprovalBusy(approval.id, false);
    }
  }

  Future<bool> _rejectApplication(
    BuildContext context,
    HealthworkerApproval approval,
  ) async {
    final reasonController = TextEditingController();
    final reason = await GlassSheet.show<String>(
      context,
      title: 'Reject application',
      subtitle: 'Give ${approval.name} a clear reason',
      child: Builder(
        builder: (reasonContext) => Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.md,
            AppSpacing.xl,
            AppSpacing.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppTextField(
                controller: reasonController,
                label: 'Reason for rejection',
                hint: 'Explain what must be corrected before reapplying.',
                maxLines: 4,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'This reason is recorded in the audit trail.',
                style: Theme.of(reasonContext).textTheme.bodySmall?.copyWith(
                  color: AppPalette.textMuted(reasonContext),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppButton(
                label: 'Continue',
                icon: AppIcons.chevronRight,
                variant: AppButtonVariant.danger,
                expand: true,
                onPressed: () {
                  final value = reasonController.text.trim();
                  if (value.length < 5) {
                    AppToast.warn(
                      reasonContext,
                      'Enter a clear reason (at least 5 characters).',
                    );
                    return;
                  }
                  Navigator.of(reasonContext, rootNavigator: true).pop(value);
                },
              ),
            ],
          ),
        ),
      ),
    );
    reasonController.dispose();
    if (reason == null || !context.mounted) return false;

    final confirmed = await AppDialog.confirm(
      context,
      title: 'Reject ${approval.name}?',
      message: 'The application will be closed and the clinician notified.',
      confirmLabel: 'Reject',
      danger: true,
      icon: AppIcons.close,
    );
    if (confirmed != true || !mounted) return false;

    _setApprovalBusy(approval.id, true);
    try {
      if (AppEnv.backendEnabled) {
        await StaffState.instance.rejectApplicationRemote(
          approval.id,
          reason: reason,
        );
      } else {
        StaffState.instance.setApproval(approval.id, 'rejected');
      }
      if (!context.mounted) return true;
      AppToast.info(context, '${approval.name} application rejected.');
      return true;
    } catch (error) {
      if (context.mounted) {
        AppToast.error(context, 'Could not reject application: $error');
      }
      return false;
    } finally {
      _setApprovalBusy(approval.id, false);
    }
  }

  Future<void> _requestInfo(
    BuildContext context,
    HealthworkerApproval approval,
  ) async {
    final messageController = TextEditingController();
    final message = await GlassSheet.show<String>(
      context,
      title: 'Request more information',
      subtitle: 'Send a message to ${approval.name}',
      child: Builder(
        builder: (messageContext) => Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.md,
            AppSpacing.xl,
            AppSpacing.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppTextField(
                controller: messageController,
                label: 'Message',
                hint: 'For example: upload a clearer copy of your license.',
                maxLines: 4,
              ),
              const SizedBox(height: AppSpacing.lg),
              AppButton(
                label: 'Send request',
                icon: AppIcons.chat,
                expand: true,
                onPressed: () {
                  final value = messageController.text.trim();
                  if (value.isEmpty) {
                    AppToast.warn(messageContext, 'Message cannot be empty.');
                    return;
                  }
                  Navigator.of(messageContext, rootNavigator: true).pop(value);
                },
              ),
            ],
          ),
        ),
      ),
    );
    messageController.dispose();
    if (message == null || !context.mounted) return;

    _setApprovalBusy(approval.id, true);
    try {
      final res = await AdminApi.instance.requestApplicationInfo(
        approval.id,
        message: message,
      );
      if (!context.mounted) return;
      AppToast.success(
        context,
        res?['message'] as String? ??
            'Information request sent to ${approval.name}.',
      );
    } catch (error) {
      if (!context.mounted) return;
      AppToast.error(context, 'Could not send request: $error');
    } finally {
      _setApprovalBusy(approval.id, false);
    }
  }

  void _setApprovalBusy(String id, bool busy) {
    if (!mounted) return;
    setState(() {
      if (busy) {
        _busyApprovalIds.add(id);
      } else {
        _busyApprovalIds.remove(id);
      }
    });
  }

  static String _statusLabel(String status) {
    if (status.isEmpty) return 'Pending';
    return '${status[0].toUpperCase()}${status.substring(1)}';
  }

  static Color _statusColor(String status) => switch (status) {
    'approved' => AppColors.success,
    'rejected' => AppColors.critical,
    _ => AppColors.warning,
  };

  @override
  Widget build(BuildContext context) {
    return RoleShell(
      scrollable: true,
      currentRoute: widget.currentRoute,
      destinations: widget.destinations.cast(),
      profileRoute: widget.profileRoute,
      notificationsRoute: widget.notificationsRoute,
      title: 'Healthworker approvals',
      subtitle: 'Verify license, approve or reject new clinicians',
      body: AnimatedBuilder(
        animation: StaffState.instance,
        builder: (context, _) {
          final approvals = StaffState.instance.approvals;
          if (_loading && approvals.isEmpty) {
            return const SizedBox(
              height: 360,
              child: AppLoadingView(
                message: 'Loading clinician applications…',
                itemCount: 3,
                padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
              ),
            );
          }

          if (_error != null && approvals.isEmpty) {
            return _ApprovalErrorCard(
              message: _error!,
              onRetry: _loadApprovals,
            );
          }

          final pending =
              StaffState.instance.approvals
                  .where((a) => a.status == 'pending')
                  .toList()
                ..sort((a, b) => b.appliedAt.compareTo(a.appliedAt));
          final decided =
              StaffState.instance.approvals
                  .where((a) => a.status != 'pending')
                  .toList()
                ..sort((a, b) => b.appliedAt.compareTo(a.appliedAt));
          if (pending.isEmpty && decided.isEmpty) {
            return const _ApprovalEmptyCard();
          }
          final handheld = ResponsiveBuilder.of(context).isHandheld;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (pending.isNotEmpty) ...[
                StaggeredEntry(
                  index: 0,
                  child: SectionLabel(
                    title: 'Applications to review',
                    icon: AppIcons.approval,
                    trailing: '${pending.length}/${approvals.length}',
                    actionLabel: _loading ? null : 'Refresh',
                    onAction: _loading ? null : _loadApprovals,
                  ),
                ),
                StaggeredEntry(
                  index: 1,
                  child: StaffListCard(
                    children: pending
                        .map(
                          (approval) => StaffListRow(
                            icon: AppIcons.approval,
                            iconColor: AppColors.adminPurple,
                            title: approval.name,
                            subtitle: [
                              approval.specialty,
                              if (approval.licenseNumber?.isNotEmpty == true)
                                approval.licenseNumber!,
                              DateFormat.MMMd().format(approval.appliedAt),
                            ].join(' · '),
                            pill: handheld ? 'REVIEW' : null,
                            pillColor: AppColors.adminPurple,
                            onTap: () => _showDetail(context, approval),
                            trailing: handheld
                                ? null
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      AppButton(
                                        label: 'Approve',
                                        size: AppButtonSize.sm,
                                        loading: _busyApprovalIds.contains(
                                          approval.id,
                                        ),
                                        onPressed:
                                            _busyApprovalIds.contains(
                                              approval.id,
                                            )
                                            ? null
                                            : () => _approveApplication(
                                                context,
                                                approval,
                                              ),
                                      ),
                                      const SizedBox(width: AppSpacing.sm),
                                      AppButton(
                                        label: 'Reject',
                                        size: AppButtonSize.sm,
                                        variant: AppButtonVariant.danger,
                                        onPressed:
                                            _busyApprovalIds.contains(
                                              approval.id,
                                            )
                                            ? null
                                            : () => _rejectApplication(
                                                context,
                                                approval,
                                              ),
                                      ),
                                    ],
                                  ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
              if (decided.isNotEmpty) ...[
                if (pending.isNotEmpty) const SizedBox(height: AppSpacing.xl),
                StaggeredEntry(
                  index: 2,
                  child: const SectionLabel(title: 'Recently reviewed'),
                ),
                StaggeredEntry(
                  index: 3,
                  child: StaffListCard(
                    children: decided
                        .map(
                          (approval) => StaffListRow(
                            icon: approval.status == 'approved'
                                ? AppIcons.check
                                : AppIcons.close,
                            iconColor: approval.status == 'approved'
                                ? AppColors.success
                                : AppColors.critical,
                            title: approval.name,
                            subtitle:
                                '${approval.specialty} · ${DateFormat.MMMd().format(approval.appliedAt)}',
                            pill: approval.status.toUpperCase(),
                            pillColor: approval.status == 'approved'
                                ? AppColors.success
                                : AppColors.critical,
                            onTap: () => _showDetail(context, approval),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.huge),
            ],
          );
        },
      ),
    );
  }
}

class _ApprovalEmptyCard extends StatelessWidget {
  const _ApprovalEmptyCard();

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: 28,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.adminPurple.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            ),
            alignment: Alignment.center,
            child: const Icon(
              AppIcons.approval,
              color: AppColors.adminPurple,
              size: 34,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'No applications',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ],
      ),
    );
  }
}

class _ApprovalErrorCard extends StatelessWidget {
  const _ApprovalErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          EmptyStateView(
            icon: AppIcons.alert,
            title: 'Could not load applications',
            message: message,
            compact: true,
          ),
          AppButton(
            label: 'Try again',
            icon: AppIcons.refresh,
            onPressed: onRetry,
          ),
          const SizedBox(height: AppSpacing.md),
        ],
      ),
    );
  }
}

class _ApprovalIdentityCard extends StatelessWidget {
  const _ApprovalIdentityCard({required this.approval});

  final HealthworkerApproval approval;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.adminPurple.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(
          color: AppColors.adminPurple.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.adminPurple.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            alignment: Alignment.center,
            child: const Icon(
              AppIcons.approval,
              color: AppColors.adminPurple,
              size: 22,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  approval.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  approval.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppPalette.textMuted(context),
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

class _ApprovalDetailRow extends StatelessWidget {
  const _ApprovalDetailRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppPalette.textMuted(context),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: valueColor ?? AppPalette.ink(context),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
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
