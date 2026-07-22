import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/realtime/session_poller.dart';
import '../../shared/constants/route_names.dart';
import '../../shared/navigation/staff_destinations.dart';
import '../../shared/state/staff_state.dart';
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
import '../../shared/widgets/section_label.dart';
import '../../shared/widgets/staff_blocks.dart';
import '../../shared/widgets/staff_filter_chip.dart';

class AdminCareRequestsView extends StatelessWidget {
  const AdminCareRequestsView({super.key});

  @override
  Widget build(BuildContext context) {
    return CareRequestsScreen(
      currentRoute: RouteNames.adminCareRequests,
      destinations: StaffDestinations.admin(),
      profileRoute: RouteNames.adminProfile,
      notificationsRoute: RouteNames.adminNotifications,
    );
  }
}

class CareRequestsScreen extends StatefulWidget {
  const CareRequestsScreen({
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
  State<CareRequestsScreen> createState() => _CareRequestsScreenState();
}

class _CareRequestsScreenState extends State<CareRequestsScreen> {
  String _filter = 'all'; // all | pending | approved | rejected

  static const _filterOptions = [
    StaffFilterOption(value: 'all', label: 'All'),
    StaffFilterOption(value: 'pending', label: 'Pending', color: AppColors.warning),
    StaffFilterOption(value: 'approved', label: 'Approved', color: AppColors.success),
    StaffFilterOption(value: 'rejected', label: 'Rejected', color: AppColors.critical),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) SessionPoller.instance.triggerNow();
    });
  }

  List<CareRequestItem> get _filtered {
    final items = StaffState.instance.careRequests;
    if (_filter == 'all') return items;
    return items.where((r) => r.status == _filter).toList();
  }

  Future<void> _approve(BuildContext context, CareRequestItem r) async {
    final ok = await AppDialog.confirm(
      context,
      title: 'Approve care request?',
      message: '${r.patient} will be matched with ${r.providerRequested}.',
      icon: AppIcons.careRequest,
    );
    if (ok != true || !context.mounted) return;
    final success = await StaffState.instance.approveCareRequestAdminRemote(r.id);
    if (!context.mounted) return;
    if (success) {
      AppToast.success(context, 'Request approved.');
    } else {
      AppToast.error(context, 'Could not approve — please retry.');
    }
  }

  Future<void> _reject(BuildContext context, CareRequestItem r) async {
    final reasonCtrl = TextEditingController();
    final confirmed = await GlassSheet.show<bool>(
      context,
      title: 'Reject care request',
      subtitle: 'Provide a reason — it will be shared with the patient.',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppTextField(
              controller: reasonCtrl,
              label: 'Reason',
              hint: 'e.g. Provider unavailable in patient region',
              maxLines: 3,
            ),
            const SizedBox(height: 20),
            AppButton(
              label: 'Confirm rejection',
              variant: AppButtonVariant.danger,
              icon: AppIcons.close,
              expand: true,
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final reason = reasonCtrl.text.trim().isEmpty
        ? 'Rejected by admin'
        : reasonCtrl.text.trim();
    final success = await StaffState.instance
        .rejectCareRequestAdminRemote(r.id, reason: reason);
    if (!context.mounted) return;
    if (success) {
      AppToast.info(context, 'Request rejected.');
    } else {
      AppToast.error(context, 'Could not reject — please retry.');
    }
  }

  Future<void> _showDetail(BuildContext context, CareRequestItem r) async {
    await GlassSheet.show<void>(
      context,
      title: 'Care request',
      subtitle: '${r.patient} → ${r.providerRequested}',
      child: Padding(
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
            _detailRow('Status', r.status.toUpperCase()),
            _detailRow('Reason', r.reason),
            _detailRow(
              'Submitted',
              DateFormat.MMMd().add_jm().format(r.createdAt),
            ),
            if (r.status == 'pending') ...[
              const SizedBox(height: AppSpacing.lg),
              AppButton(
                label: 'Approve',
                icon: AppIcons.check,
                expand: true,
                onPressed: () async {
                  Navigator.of(context).pop();
                  await _approve(context, r);
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
                  await _reject(context, r);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            Expanded(child: Text(value)),
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
      title: 'Care requests',
      subtitle: 'Patient ↔ provider matchmaking queue',
      body: AnimatedBuilder(
        animation: StaffState.instance,
        builder: (context, _) {
          final pending =
              StaffState.instance.careRequests.where((r) => r.status == 'pending').length;
          final handheld = ResponsiveBuilder.of(context).isHandheld;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (pending > 0)
                GlassCard(
                  frosted: true,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppColors.warning,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$pending request${pending == 1 ? '' : 's'} awaiting action',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: AppColors.warning,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              StaffFilterChipBar(
                options: _filterOptions,
                selected: _filter,
                onSelected: (v) => setState(() => _filter = v),
              ),
              const SizedBox(height: 12),
              if (_filtered.isEmpty)
                GlassCard(
                  frosted: true,
                  child: EmptyStateView(
                    icon: AppIcons.careRequest,
                    title: _filter == 'all'
                        ? 'No care requests'
                        : 'No $_filter requests',
                    compact: true,
                  ),
                )
              else ...[
                SectionLabel(
                  title: _filter == 'all'
                      ? 'All requests'
                      : '${_filter[0].toUpperCase()}${_filter.substring(1)}',
                  icon: AppIcons.careRequest,
                  trailing: '${_filtered.length}',
                ),
                StaffListCard(
                  children: _filtered
                      .map((r) => StaffListRow(
                            icon: AppIcons.careRequest,
                            iconColor: _statusColor(r.status),
                            title: '${r.patient} → ${r.providerRequested}',
                            subtitle:
                                '${r.reason}\n${DateFormat.MMMd().add_jm().format(r.createdAt)}',
                            pill: r.status == 'pending' && handheld
                                ? 'Review'
                                : r.status.toUpperCase(),
                            pillColor: _statusColor(r.status),
                            onTap: () => _showDetail(context, r),
                            trailing: r.status == 'pending' && !handheld
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      AppButton(
                                        label: 'Approve',
                                        size: AppButtonSize.sm,
                                        onPressed: () => _approve(context, r),
                                      ),
                                      const SizedBox(width: 6),
                                      AppButton(
                                        label: 'Reject',
                                        size: AppButtonSize.sm,
                                        variant: AppButtonVariant.danger,
                                        onPressed: () => _reject(context, r),
                                      ),
                                    ],
                                  )
                                : null,
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

  Color _statusColor(String status) => switch (status) {
        'approved' => AppColors.success,
        'rejected' => AppColors.critical,
        _ => AppColors.warning,
      };
}
