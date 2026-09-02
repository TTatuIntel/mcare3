import 'package:flutter/material.dart';

import '../../core/realtime/realtime_refresh_mixin.dart';
import '../auth/auth_state.dart';
import '../dashboard/admin_workspace_catalog.dart';
import '../account/account_preferences_list.dart';
import '../account/staff_assistant_workspace_section.dart';
import '../constants/route_names.dart';
import '../models/profile_completion.dart';
import '../models/user_role.dart';
import '../navigation/profile_navigation.dart';
import '../profile/profile_header_card.dart';
import '../profile/profile_sections.dart';
import '../services/admin_session_service.dart';
import '../services/doctor_session_service.dart';
import '../settings/widgets/settings_quick_actions.dart';
import '../state/messages_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'app_button.dart';
import 'app_icons.dart';
import 'app_message_bubble.dart';
import 'empty_state.dart';
import 'glass_card.dart';
import 'glass_floating_button.dart';
import 'new_conversation_sheet.dart';
import 'notification_components.dart';
import 'section_label.dart';
import 'role_shell.dart';
import 'profile_completion_heart.dart';
import 'staff_blocks.dart';

/// Staff notifications — shared panel with role-aware refresh and hub links.
class StaffNotificationsView extends StatefulWidget {
  const StaffNotificationsView({
    super.key,
    required this.currentRoute,
    required this.destinations,
    required this.profileRoute,
    this.notificationsRoute,
    this.header,
  });

  final String currentRoute;
  final List<RoleNavDestination> destinations;
  final String profileRoute;
  final String? notificationsRoute;

  /// Optional widget rendered above the notifications panel (e.g. a date
  /// header). Doctors/assistants pass none; admin passes a [PatientDateHeader].
  final Widget? header;

  @override
  State<StaffNotificationsView> createState() => _StaffNotificationsViewState();
}

class _StaffNotificationsViewState extends State<StaffNotificationsView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    final role = AuthState.instance.user?.role;
    if (role == UserRole.admin || role == UserRole.mcareAssistant) {
      await AdminSessionService.instance.syncFromApi(background: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = AuthState.instance.user?.role;
    final subtitle = role == UserRole.admin
        ? 'Operational alerts · approvals · SOS'
        : 'Unified inbox — alerts, messages and updates';

    return RoleShell(
      currentRoute: widget.currentRoute,
      destinations: widget.destinations,
      profileRoute: widget.profileRoute,
      notificationsRoute: widget.notificationsRoute ?? widget.currentRoute,
      title: 'Notifications',
      subtitle: subtitle,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.header != null) ...[
            widget.header!,
            const SizedBox(height: AppSpacing.sm),
          ],
          const NotificationsPanel(),
          if (role != null) ...[
            const SizedBox(height: AppSpacing.lg),
            SectionLabel(
              title: 'More from your account',
              icon: AppIcons.profile,
            ),
            const SizedBox(height: AppSpacing.sm),
            AccountHubQuickLinks(role: role, currentRoute: widget.currentRoute),
          ],
        ],
      ),
    );
  }
}

/// Unified staff messages list (uses the same MessagesState the patient uses).
class StaffMessagesView extends StatefulWidget {
  const StaffMessagesView({
    super.key,
    required this.currentRoute,
    required this.destinations,
    required this.profileRoute,
    required this.threadRouteName,
  });

  final String currentRoute;
  final List<RoleNavDestination> destinations;
  final String profileRoute;
  final String threadRouteName;

  @override
  State<StaffMessagesView> createState() => _StaffMessagesViewState();
}

class _StaffMessagesViewState extends State<StaffMessagesView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    final role = AuthState.instance.user?.role;
    if (role == UserRole.admin || role == UserRole.mcareAssistant) {
      await AdminSessionService.instance.syncFromApi(background: true);
    } else if (role == UserRole.doctor) {
      await DoctorSessionService.instance.syncFromApi();
    }
    if (mounted) setState(() {});
  }

  bool get _canStartConversation {
    final role = AuthState.instance.user?.role;
    return role == UserRole.admin || role == UserRole.mcareAssistant;
  }

  void _openNewConversation() {
    NewConversationSheet.show(context, threadRouteName: widget.threadRouteName);
  }

  @override
  Widget build(BuildContext context) {
    final accent =
        AuthState.instance.user?.role.accent ?? AppColors.brandIndigo;

    return RoleShell(
      currentRoute: widget.currentRoute,
      destinations: widget.destinations,
      profileRoute: widget.profileRoute,
      title: 'Messages',
      subtitle: 'Care coordination · patient threads',
      floatingActionButton: _canStartConversation
          ? GlassFloatingButton(
              icon: AppIcons.add,
              label: 'New',
              accent: accent,
              onPressed: _openNewConversation,
            )
          : null,
      body: AnimatedBuilder(
        animation: MessagesState.instance,
        builder: (context, _) {
          final conversations = MessagesState.instance.conversations;
          if (conversations.isEmpty) {
            return GlassCard(
              frosted: true,
              child: EmptyStateView(
                icon: AppIcons.chat,
                title: 'No conversations yet',
                message: _canStartConversation
                    ? 'Start a thread with a patient or care-team member.'
                    : 'Patient messages and care-team threads will appear here.',
                compact: true,
                actionLabel: _canStartConversation ? 'New conversation' : null,
                onAction: _canStartConversation ? _openNewConversation : null,
              ),
            );
          }
          return StaffListCard(
            children: conversations
                .map(
                  (c) => StaffListRow(
                    icon: AppIcons.chat,
                    title: c.participant.name,
                    subtitle: c.lastMessage.body,
                    pill: c.unreadCount > 0 ? '${c.unreadCount} new' : null,
                    onTap: () => Navigator.of(
                      context,
                    ).pushNamed(widget.threadRouteName, arguments: c.id),
                  ),
                )
                .toList(),
          );
        },
      ),
    );
  }
}

/// Generic chat thread view — wraps shared MessagesState so the same
/// component renders for doctor, admin and assistant chats.
class StaffChatThreadView extends StatefulWidget {
  const StaffChatThreadView({
    super.key,
    required this.conversationId,
    required this.currentRoute,
    required this.destinations,
    required this.profileRoute,
  });

  final String conversationId;
  final String currentRoute;
  final List<RoleNavDestination> destinations;
  final String profileRoute;

  @override
  State<StaffChatThreadView> createState() => _StaffChatThreadViewState();
}

class _StaffChatThreadViewState extends State<StaffChatThreadView>
    with RealtimeRefreshMixin<StaffChatThreadView> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    watchRealtime(const {'messages'}, _refreshThread);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshThread();
    });
  }

  Future<void> _refreshThread() async {
    await MessagesState.instance.loadThread(widget.conversationId);
    final conversation = MessagesState.instance.byId(widget.conversationId);
    if (conversation != null && conversation.unreadCount > 0) {
      await MessagesState.instance.markRead(widget.conversationId);
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    final ok = await MessagesState.instance.send(widget.conversationId, text);
    if (ok.isEmpty) return;
    _input.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: MessagesState.instance,
      builder: (context, _) {
        final conv = MessagesState.instance.byId(widget.conversationId);
        if (conv == null) {
          return RoleShell(
            currentRoute: widget.currentRoute,
            destinations: widget.destinations,
            profileRoute: widget.profileRoute,
            title: 'Conversation',
            body: GlassCard(
              frosted: true,
              child: EmptyStateView(
                icon: AppIcons.chat,
                title: 'Conversation not found',
                compact: true,
              ),
            ),
          );
        }
        final messages = MessagesState.instance.thread(widget.conversationId);
        return RoleShell(
          currentRoute: widget.currentRoute,
          destinations: widget.destinations,
          profileRoute: widget.profileRoute,
          scrollable: false,
          title: conv.participant.name,
          subtitle: conv.participant.specialty ?? conv.participant.role,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  children: [
                    for (final m in messages)
                      AppMessageBubble(
                        body: m.body,
                        sentAt: m.sentAt,
                        isMine: m.senderId == 'me',
                        author: m.senderId == 'me'
                            ? null
                            : conv.participant.name,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      style: Theme.of(context).textTheme.bodyMedium,
                      decoration: InputDecoration(
                        hintText: 'Reply to ${conv.participant.name}',
                        filled: true,
                        fillColor: AppPalette.surfaceAlt(context),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusPill,
                          ),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                          vertical: AppSpacing.sm,
                        ),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  AppButton.icon(
                    icon: AppIcons.send,
                    semanticLabel: 'Send',
                    onPressed: _send,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Generic staff profile — reads [AuthState] for the logged-in user.
class StaffProfileView extends StatefulWidget {
  const StaffProfileView({
    super.key,
    required this.currentRoute,
    required this.destinations,
    this.notificationsRoute,
  });

  final String currentRoute;
  final List<RoleNavDestination> destinations;
  final String? notificationsRoute;

  @override
  State<StaffProfileView> createState() => _StaffProfileViewState();
}

class _StaffProfileViewState extends State<StaffProfileView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncWorkspace());
  }

  Future<void> _syncWorkspace() async {
    final role = AuthState.instance.user?.role;
    if (role == UserRole.admin || role == UserRole.mcareAssistant) {
      await AdminSessionService.instance.syncFromApi(background: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AuthState.instance,
      builder: (context, _) {
        final user = AuthState.instance.user;
        if (user == null) {
          return RoleShell(
            currentRoute: widget.currentRoute,
            destinations: widget.destinations,
            profileRoute: widget.currentRoute,
            notificationsRoute: widget.notificationsRoute,
            title: 'Profile',
            body: GlassCard(
              frosted: true,
              child: EmptyStateView(
                icon: AppIcons.profile,
                title: 'Not signed in',
                message: 'Sign in to view your profile.',
                compact: true,
              ),
            ),
          );
        }

        final completion = ProfileCompletion.forUser(user: user);

        return RoleShell(
          currentRoute: widget.currentRoute,
          destinations: widget.destinations,
          profileRoute: widget.currentRoute,
          notificationsRoute: widget.notificationsRoute,
          title: 'Profile',
          subtitle: '${user.role.label} · ${user.uniqueId}',
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ProfileHeaderCard(
                user: user,
                completionPercent: completion.percent,
                editLabel: user.isProfileComplete
                    ? 'Edit profile'
                    : 'Complete profile',
                onEdit: () =>
                    ProfileNavigation.openEditOrCompleteProfile(context),
                warning: user.isProfileComplete
                    ? null
                    : 'Complete your profile so your workspace is fully set up.',
              ),
              if (!completion.isComplete) ...[
                const SizedBox(height: AppSpacing.sm),
                GlassCard(
                  frosted: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  child: ProfileCompletionCard(
                    percent: completion.percent,
                    incompleteLabels: completion.incompleteItems
                        .map((i) => i.label)
                        .toList(),
                    onTap: () =>
                        ProfileNavigation.openEditOrCompleteProfile(context),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              ProfileAccountSection(
                user: user,
                onEdit: () =>
                    ProfileNavigation.openEditOrCompleteProfile(context),
              ),
              if (user.role == UserRole.mcareAssistant) ...[
                const SizedBox(height: AppSpacing.md),
                SettingsQuickActionsBar(
                  actions: [
                    SettingsQuickActionDef(
                      icon: AppIcons.edit,
                      label: user.isProfileComplete
                          ? 'Edit profile'
                          : 'Complete profile',
                      onTap: () =>
                          ProfileNavigation.openEditOrCompleteProfile(context),
                    ),
                    SettingsQuickActionDef(
                      icon: AppIcons.support,
                      label: 'Ticket inbox',
                      badge: AdminWorkspaceCounts.openSupport > 0
                          ? '${AdminWorkspaceCounts.openSupport}'
                          : null,
                      onTap: () => Navigator.of(
                        context,
                      ).pushNamed(RouteNames.assistantSupport),
                    ),
                    if (AuthState.instance.hasAssistantPermission(
                      AssistantPermissions.canCreateUsers,
                    ))
                      SettingsQuickActionDef(
                        icon: AppIcons.lock,
                        label: 'Users & passwords',
                        onTap: () => Navigator.of(
                          context,
                        ).pushNamed(RouteNames.assistantUsers),
                      ),
                    SettingsQuickActionDef(
                      icon: AppIcons.settings,
                      label: 'Settings',
                      onTap: () => Navigator.of(
                        context,
                      ).pushNamed(RouteNames.assistantSettings),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              // Admin uses AdminProfileView — StaffProfileView here only ever
              // renders for doctor + mcareAssistant (see StaffRouteFactory).
              if (user.role == UserRole.mcareAssistant) ...[
                const StaffAssistantWorkspaceSection(),
                const SizedBox(height: AppSpacing.md),
              ],
              SectionLabel(
                title: 'Account & preferences',
                icon: AppIcons.settings,
              ),
              const SizedBox(height: AppSpacing.sm),
              AccountPreferencesList(
                role: user.role,
                excludeRoutes: {
                  if (user.role == UserRole.mcareAssistant) ...{
                    RouteNames.assistantSupport,
                    RouteNames.assistantUsers,
                    RouteNames.assistantAudit,
                  },
                },
              ),
              const SizedBox(height: AppSpacing.md),
              const ProfileSecuritySection(),
            ],
          ),
        );
      },
    );
  }
}

class StaffProfileDetail extends StatelessWidget {
  const StaffProfileDetail({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppPalette.textMuted(context)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppPalette.textMuted(context),
                  ),
                ),
                Text(value, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
