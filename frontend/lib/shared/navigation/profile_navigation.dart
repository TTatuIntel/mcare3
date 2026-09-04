import 'package:flutter/material.dart';

import '../profile/edit_account_sheet.dart';
import '../auth/auth_state.dart';
import '../constants/route_names.dart';
import '../models/user_role.dart';
import '../navigation/navigation_roots.dart';
import '../navigation/root_navigator.dart';
import '../navigation/staff_destinations.dart';
import '../widgets/app_icons.dart';
import '../widgets/patient_bottom_nav.dart';

/// Result returned when an account [GlassSheet] is dismissed via a menu action.
///
/// Using dialog results (instead of pop-then-push in the same frame) is the
/// reliable way to navigate from a modal sheet on Flutter web — the push runs
/// only after the sheet route is fully removed.
class AccountSheetAction {
  const AccountSheetAction._({this.route, this.openEdit = false});

  const AccountSheetAction.navigate(String route)
    : this._(route: route, openEdit: false);

  const AccountSheetAction.editProfile() : this._(route: null, openEdit: true);

  final String? route;
  final bool openEdit;
}

/// Role-aware profile menu routes and items — one source of truth.
class ProfileNavigation {
  ProfileNavigation._();

  static String subtitleFor(UserRole role) => switch (role) {
    UserRole.patient => 'Profile, care team and settings',
    UserRole.doctor => 'Profile and workspace settings',
    UserRole.admin => 'Profile and administration',
    UserRole.mcareAssistant => 'Profile and assistant tools',
    UserRole.externalDoctor => 'Profile and consult access',
    UserRole.guest => 'Account',
  };

  static String profileRouteFor(UserRole role) => switch (role) {
    UserRole.doctor => RouteNames.doctorProfile,
    UserRole.admin => RouteNames.adminProfile,
    UserRole.mcareAssistant => RouteNames.assistantProfile,
    UserRole.externalDoctor => RouteNames.externalDoctor,
    _ => RouteNames.patientProfile,
  };

  static String? settingsRouteFor(UserRole role) => switch (role) {
    UserRole.patient => RouteNames.patientSettings,
    UserRole.doctor => RouteNames.doctorSettings,
    UserRole.admin => RouteNames.adminSettings,
    UserRole.mcareAssistant => RouteNames.assistantSettings,
    _ => null,
  };

  static String? supportRouteFor(UserRole role) => switch (role) {
    UserRole.patient => RouteNames.patientSupport,
    UserRole.admin => RouteNames.adminSupport,
    UserRole.mcareAssistant => RouteNames.assistantSupport,
    _ => null,
  };

  static String? usersRouteFor(UserRole role) => switch (role) {
    UserRole.admin => RouteNames.adminUsers,
    UserRole.mcareAssistant => RouteNames.assistantUsers,
    _ => null,
  };

  static String? notificationsRouteFor(UserRole role) => switch (role) {
    UserRole.patient => RouteNames.patientNotifications,
    UserRole.doctor => RouteNames.doctorNotifications,
    UserRole.admin => RouteNames.adminNotifications,
    UserRole.mcareAssistant => RouteNames.assistantNotifications,
    _ => null,
  };

  /// Messages list for the role — surfaced in the app header next to the bell.
  static String? messagesRouteFor(UserRole role) => switch (role) {
    UserRole.patient => RouteNames.patientMessages,
    UserRole.doctor => RouteNames.doctorMessages,
    UserRole.admin => RouteNames.adminMessages,
    UserRole.mcareAssistant => RouteNames.assistantMessages,
    _ => null,
  };

  static String? completeProfileRouteFor(UserRole role) => switch (role) {
    UserRole.admin => RouteNames.adminCompleteProfile,
    UserRole.mcareAssistant => RouteNames.assistantCompleteProfile,
    UserRole.doctor => RouteNames.doctorCompleteProfile,
    _ => null,
  };

  /// Apply an [AccountSheetAction] after the account sheet has fully closed.
  static Future<void> applySheetAction(
    BuildContext context,
    AccountSheetAction? action,
  ) async {
    if (action == null) return;
    if (!context.mounted) return;

    if (action.openEdit) {
      openEditOrCompleteProfile(context);
      return;
    }

    final route = action.route;
    if (route == null || route.isEmpty) return;

    final nav = Navigator.of(context, rootNavigator: true);
    // Profile-menu destinations (care team, settings, SOS, profile, support…)
    // are all "root" tab routes. They must REPLACE the stack — exactly like the
    // bottom nav — otherwise `RootNavigationScope.ensureCleanRootStack` sees a
    // poppable route on mount and immediately pops it back to the dashboard
    // (the "sheet closes, page never opens" bug). Non-root drill-down routes
    // still push normally so their back button works.
    if (NavigationRoots.isRootRoute(route)) {
      await nav.pushNamedAndRemoveUntil(route, (_) => false);
    } else {
      await nav.pushNamed(route);
    }
  }

  /// Close an account [GlassSheet] by returning [action] as the dialog result.
  static void completeSheet(
    BuildContext sheetContext,
    AccountSheetAction action,
  ) {
    final nav = Navigator.of(sheetContext, rootNavigator: true);
    if (nav.canPop()) {
      nav.pop(action);
    }
  }

  /// Legacy helper — prefer [completeSheet] + [applySheetAction].
  ///
  /// Captures the root [NavigatorState] BEFORE popping so the subsequent
  /// push does not depend on a disposed overlay context.
  static void navigateFromSheet(BuildContext sheetContext, String route) {
    completeSheet(sheetContext, AccountSheetAction.navigate(route));
  }

  /// Close sheet then run [action] with the root [BuildContext].
  static void runFromSheet(
    BuildContext sheetContext,
    void Function(BuildContext rootContext) action,
  ) {
    final rootNav = Navigator.of(sheetContext, rootNavigator: true);
    if (rootNav.canPop()) rootNav.pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = rootNavigatorKey.currentContext ?? rootNav.context;
      if (ctx.mounted) action(ctx);
    });
  }

  /// Edit profile when complete; full-screen complete-profile when not.
  static void openEditOrCompleteProfile(BuildContext context) {
    final user = AuthState.instance.user;
    if (user == null) return;
    if (!user.isProfileComplete) {
      final route = completeProfileRouteFor(user.role);
      if (route != null) {
        Navigator.of(context, rootNavigator: true).pushNamed(route);
        return;
      }
    }
    // ignore: discarded_futures
    EditAccountSheet.show(context);
  }

  /// Same as [openEditOrCompleteProfile] after closing an account sheet.
  static void openEditOrCompleteFromSheet(BuildContext sheetContext) {
    completeSheet(sheetContext, const AccountSheetAction.editProfile());
  }

  /// Routes already reachable from the role's primary bottom navigation.
  ///
  /// The account sheet uses this to guarantee it never re-exposes a destination
  /// that the persistent bottom nav / rail already shows — no duplicate icons in
  /// quick actions or menu rows anywhere in the app.
  static Set<String> primaryNavRoutesFor(UserRole role) => switch (role) {
    UserRole.patient =>
      PatientBottomNav.destinations.map((d) => d.route).toSet(),
    UserRole.doctor =>
      StaffDestinations.doctor()
          .where((d) => d.showInBottomNav)
          .map((d) => d.route)
          .toSet(),
    UserRole.admin =>
      StaffDestinations.admin()
          .where((d) => d.showInBottomNav)
          .map((d) => d.route)
          .toSet(),
    UserRole.mcareAssistant =>
      StaffDestinations.assistant()
          .where((d) => d.showInBottomNav)
          .map((d) => d.route)
          .toSet(),
    _ => <String>{},
  };

  /// Compact quick-action chips shown between "Edit profile" and the menu.
  ///
  /// Rules:
  ///   - Chips are personal / ops shortcuts that are NOT already top-level tabs
  ///     (e.g. patient Documents / My care team). Any destination present in the
  ///     primary bottom nav is filtered out below so nothing is duplicated.
  ///   - Alerts stays because it becomes a distinct "personal" angle
  ///     (e.g. "My alerts") not shown as a top-level tab.
  ///   - Support is deliberately omitted for admin/assistant — it's already
  ///     in the primary nav rail with an unread badge.
  static List<ProfileQuickAction> quickActionsFor(UserRole role) {
    final actions = switch (role) {
      // Documents already lives in the patient dashboard quick-actions bar and
      // My care team is surfaced as a full menu row below, so patients have no
      // chip-style quick actions here (avoids a lone off-design chip).
      UserRole.patient => const <ProfileQuickAction>[],
      UserRole.doctor => const [
        // Schedule (Appointments) and Messages (Chat) are top-level tabs, so
        // they are intentionally NOT repeated here. Alerts is a distinct
        // "personal" angle not shown as a tab.
        ProfileQuickAction(
          icon: AppIcons.alert,
          label: 'My alerts',
          route: RouteNames.doctorAlerts,
        ),
        ProfileQuickAction(
          icon: AppIcons.records,
          label: 'Reports',
          route: RouteNames.doctorReports,
        ),
      ],
      UserRole.admin => const [
        // Users is a top-level tab, so it is intentionally NOT repeated here.
        // Activity (audit) has no tab, so it earns a shortcut.
        ProfileQuickAction(
          icon: AppIcons.audit,
          label: 'Activity',
          route: RouteNames.adminAudit,
        ),
      ],
      // Assistant ops (Users, Activity, …) all live in the nav rail / More
      // sheet, so surfacing them here would duplicate. Settings stays as a
      // menu row below.
      UserRole.mcareAssistant => const <ProfileQuickAction>[],
      _ => const <ProfileQuickAction>[],
    };

    // Never repeat a top-level tab or the profile row (opened by the header).
    final reserved = primaryNavRoutesFor(role)..add(profileRouteFor(role));
    return actions.where((a) => !reserved.contains(a.route)).toList();
  }

  /// Menu items shown BELOW the identity header + Edit-profile button.
  ///
  /// Invariants:
  ///   1. No "Profile" row — identity header already opens profile.
  ///   2. No "Notifications" row — RoleShell bell already opens inbox.
  ///   3. No "Support" row for admin/assistant — primary nav rail exposes it.
  ///   4. Admin/assistant ops (users, activity) live in [quickActionsFor] only.
  ///   5. No patient "Emergency SOS" row — SOS is a one-tap action, not a
  ///      settings destination, so it lives at the end of the patient home page
  ///      and on the Care tab. The account sheet instead shows SOS *readiness*
  ///      (contacts, location sharing) in its emergency summary, which links to
  ///      the same page without duplicating the red action row.
  static List<ProfileMenuEntry> menuFor(UserRole role) {
    final settings = settingsRouteFor(role);
    final support = supportRouteFor(role);

    final items = switch (role) {
      UserRole.patient => [
        const ProfileMenuEntry(
          icon: AppIcons.careTeam,
          label: 'My care team',
          subtitle: 'Your doctors and specialists',
          route: RouteNames.patientCareTeam,
        ),
        if (settings != null)
          ProfileMenuEntry(
            icon: AppIcons.settings,
            label: 'Settings',
            subtitle: 'Appearance, alerts, privacy',
            route: settings,
          ),
        if (support != null)
          ProfileMenuEntry(
            icon: AppIcons.support,
            label: 'Support',
            subtitle: 'Talk to the care team',
            route: support,
          ),
      ],
      UserRole.doctor => [
        const ProfileMenuEntry(
          icon: AppIcons.sos,
          label: 'SOS hub',
          subtitle: 'Respond to patient emergencies',
          route: RouteNames.doctorSos,
          danger: true,
        ),
        if (settings != null)
          ProfileMenuEntry(
            icon: AppIcons.settings,
            label: 'Settings',
            subtitle: 'Appearance, alerts, privacy',
            route: settings,
          ),
      ],
      UserRole.admin => [
        if (settings != null)
          ProfileMenuEntry(
            icon: AppIcons.settings,
            label: 'Settings',
            subtitle: 'Appearance, alerts, privacy',
            route: settings,
          ),
        const ProfileMenuEntry(
          icon: AppIcons.system,
          label: 'Platform system',
          subtitle: 'Runtime, data, access',
          route: RouteNames.adminSystem,
        ),
      ],
      UserRole.mcareAssistant => [
        if (settings != null)
          ProfileMenuEntry(
            icon: AppIcons.settings,
            label: 'Settings',
            subtitle: 'Appearance, alerts, privacy',
            route: settings,
          ),
      ],
      UserRole.externalDoctor => const <ProfileMenuEntry>[],
      UserRole.guest => const <ProfileMenuEntry>[],
    };

    // A menu row must not repeat a tab, the profile row, or a quick action —
    // so the same destination never appears twice anywhere in the sheet.
    final reserved = primaryNavRoutesFor(role)
      ..add(profileRouteFor(role))
      ..addAll(quickActionsFor(role).map((a) => a.route));
    return items.where((e) => !reserved.contains(e.route)).toList();
  }
}

class ProfileQuickAction {
  const ProfileQuickAction({
    required this.icon,
    required this.label,
    required this.route,
  });

  final IconData icon;
  final String label;
  final String route;
}

class ProfileMenuEntry {
  const ProfileMenuEntry({
    required this.icon,
    required this.label,
    required this.route,
    this.subtitle,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final String route;
  final bool danger;
}
