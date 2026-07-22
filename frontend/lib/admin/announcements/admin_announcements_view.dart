import 'package:flutter/material.dart';

import '../../core/api/admin_api.dart';
import '../../shared/constants/route_names.dart';
import '../../shared/navigation/staff_destinations.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_loading_view.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/glass_sheet.dart';
import '../../shared/widgets/role_shell.dart';
import '../../shared/widgets/staff_blocks.dart';

class AdminAnnouncementsView extends StatelessWidget {
  const AdminAnnouncementsView({super.key});

  @override
  Widget build(BuildContext context) => AnnouncementsScreen(
        currentRoute: RouteNames.adminAnnouncements,
        destinations: StaffDestinations.admin(),
        profileRoute: RouteNames.adminProfile,
        notificationsRoute: RouteNames.adminNotifications,
      );
}

/// Platform announcements — create, schedule, publish to audiences.
class AnnouncementsScreen extends StatefulWidget {
  const AnnouncementsScreen({
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
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;

  static const _audiences = [
    'all',
    'patients',
    'doctors',
    'healthworkers',
    'mcare_assistant',
    'admin',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await AdminApi.instance.listAnnouncements();
      if (mounted) {
        setState(() {
          _items = rows;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _create() async {
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    String audience = 'all';

    final ok = await GlassSheet.show<bool>(
      context,
      title: 'New announcement',
      subtitle: 'Broadcast to a target audience',
      child: StatefulBuilder(
        builder: (ctx, setSt) => Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppTextField(
                controller: titleCtrl,
                label: 'Title',
                prefixIcon: AppIcons.announcements,
              ),
              const SizedBox(height: AppSpacing.sm),
              AppTextField(
                controller: bodyCtrl,
                label: 'Body',
                maxLines: 4,
              ),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<String>(
                initialValue: audience,
                decoration: const InputDecoration(labelText: 'Audience'),
                items: _audiences
                    .map((a) => DropdownMenuItem(value: a, child: Text(a)))
                    .toList(),
                onChanged: (v) => setSt(() => audience = v ?? 'all'),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppButton(
                label: 'Create draft',
                icon: AppIcons.add,
                expand: true,
                onPressed: () async {
                  if (titleCtrl.text.trim().isEmpty ||
                      bodyCtrl.text.trim().isEmpty) {
                    AppToast.warn(ctx, 'Title and body are required.');
                    return;
                  }
                  try {
                    await AdminApi.instance.createAnnouncement({
                      'title': titleCtrl.text.trim(),
                      'body': bodyCtrl.text.trim(),
                      'audience': audience,
                    });
                    if (ctx.mounted) Navigator.of(ctx).pop(true);
                  } catch (e) {
                    if (ctx.mounted) {
                      AppToast.error(ctx, 'Could not create draft: $e');
                    }
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );

    if (ok == true && mounted) {
      AppToast.success(context, 'Announcement created.');
      await _load();
    }
  }

  Future<void> _togglePublish(Map<String, dynamic> item) async {
    final id = item['id'] as String;
    final publish = !(item['is_published'] as bool? ?? false);
    try {
      await AdminApi.instance.publishAnnouncement(id, publish: publish);
      if (!mounted) return;
      AppToast.show(
        context,
        message: publish ? 'Published.' : 'Unpublished.',
      );
    } catch (e) {
      if (mounted) AppToast.error(context, 'Could not update: $e');
    }
    if (mounted) await _load();
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    try {
      await AdminApi.instance.deleteAnnouncement(item['id'] as String);
      if (!mounted) return;
      AppToast.show(context, message: 'Deleted.');
    } catch (e) {
      if (mounted) AppToast.error(context, 'Could not delete: $e');
    }
    if (mounted) await _load();
  }

  Future<void> _edit(Map<String, dynamic> item) async {
    final titleCtrl =
        TextEditingController(text: item['title'] as String? ?? '');
    final bodyCtrl = TextEditingController(text: item['body'] as String? ?? '');
    String audience = item['audience'] as String? ?? 'all';

    final ok = await GlassSheet.show<bool>(
      context,
      title: 'Edit announcement',
      subtitle: 'Update draft before publishing',
      child: StatefulBuilder(
        builder: (ctx, setSt) => Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppTextField(
                controller: titleCtrl,
                label: 'Title',
                prefixIcon: AppIcons.announcements,
              ),
              const SizedBox(height: AppSpacing.sm),
              AppTextField(
                controller: bodyCtrl,
                label: 'Body',
                maxLines: 4,
              ),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<String>(
                initialValue: audience,
                decoration: const InputDecoration(labelText: 'Audience'),
                items: _audiences
                    .map((a) => DropdownMenuItem(value: a, child: Text(a)))
                    .toList(),
                onChanged: (v) => setSt(() => audience = v ?? 'all'),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppButton(
                label: 'Save changes',
                icon: AppIcons.check,
                expand: true,
                onPressed: () async {
                  if (titleCtrl.text.trim().isEmpty ||
                      bodyCtrl.text.trim().isEmpty) {
                    AppToast.warn(ctx, 'Title and body are required.');
                    return;
                  }
                  try {
                    await AdminApi.instance.updateAnnouncement(
                      item['id'] as String,
                      {
                        'title': titleCtrl.text.trim(),
                        'body': bodyCtrl.text.trim(),
                        'audience': audience,
                      },
                    );
                    if (ctx.mounted) Navigator.of(ctx).pop(true);
                  } catch (e) {
                    if (ctx.mounted) {
                      AppToast.error(ctx, 'Could not save changes: $e');
                    }
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );

    if (ok == true && mounted) {
      AppToast.success(context, 'Announcement updated.');
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return RoleShell(
      currentRoute: widget.currentRoute,
      destinations: widget.destinations.cast(),
      profileRoute: widget.profileRoute,
      notificationsRoute: widget.notificationsRoute,
      title: 'Announcements',
      subtitle: 'Broadcast updates to patients and staff',
      scrollable: false,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(AppIcons.add),
        label: const Text('New'),
        backgroundColor: AppColors.adminPurple,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const AppLoadingView()
          : _error != null
              ? EmptyStateView(
                  icon: AppIcons.alert,
                  title: 'Could not load',
                  message: _error!,
                  actionLabel: 'Retry',
                  onAction: _load,
                )
              : _items.isEmpty
                  ? const EmptyStateView(
                      icon: AppIcons.announcements,
                      title: 'No announcements',
                      message: 'Create a draft to broadcast platform updates.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 88),
                      itemCount: _items.length,
                      separatorBuilder: (_, i) =>
                          const SizedBox(height: AppSpacing.xs),
                      itemBuilder: (context, i) {
                        final item = _items[i];
                        final published =
                            item['is_published'] as bool? ?? false;
                        final live = item['is_live'] as bool? ?? false;
                        return GlassCard(
                          frosted: true,
                          child: StaffListRow(
                            icon: AppIcons.announcements,
                            iconColor: live
                                ? AppColors.success
                                : AppPalette.textMuted(context),
                            title: item['title'] as String? ?? '',
                            subtitle:
                                '${item['audience']} · ${published ? (live ? 'Live' : 'Scheduled') : 'Draft'}',
                            pill: published ? 'Published' : 'Draft',
                            pillColor: published
                                ? AppColors.success
                                : AppColors.warning,
                            onTap: () => GlassSheet.show(
                              context,
                              title: item['title'] as String? ?? '',
                              subtitle: item['audience'] as String? ?? '',
                              child: Padding(
                                padding: const EdgeInsets.all(AppSpacing.lg),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(item['body'] as String? ?? ''),
                                    const SizedBox(height: AppSpacing.lg),
                                    AppButton(
                                      label: published
                                          ? 'Unpublish'
                                          : 'Publish',
                                      icon: published
                                          ? AppIcons.visibilityOff
                                          : AppIcons.check,
                                      onPressed: () {
                                        Navigator.of(context).pop();
                                        _togglePublish(item);
                                      },
                                    ),
                                    const SizedBox(height: AppSpacing.sm),
                                    if (!published)
                                      AppButton(
                                        label: 'Edit draft',
                                        icon: AppIcons.edit,
                                        variant: AppButtonVariant.secondary,
                                        onPressed: () {
                                          Navigator.of(context).pop();
                                          _edit(item);
                                        },
                                      ),
                                    if (!published)
                                      const SizedBox(height: AppSpacing.sm),
                                    AppButton(
                                      label: 'Delete',
                                      icon: AppIcons.delete,
                                      variant: AppButtonVariant.danger,
                                      onPressed: () {
                                        Navigator.of(context).pop();
                                        _delete(item);
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}
