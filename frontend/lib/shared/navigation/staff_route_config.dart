import '../constants/route_names.dart';
import '../navigation/staff_destinations.dart';
import '../navigation/role_nav_destination.dart';
import '../models/user_role.dart';

/// Central config for shared staff screens — eliminates per-role wrapper files.
class StaffRouteConfig {
  const StaffRouteConfig({
    required this.role,
    required this.currentRoute,
    required this.destinations,
    required this.profileRoute,
    required this.notificationsRoute,
    this.messagesRoute,
    this.chatThreadRoute,
  });

  final UserRole role;
  final String currentRoute;
  final List<RoleNavDestination> destinations;
  final String profileRoute;
  final String notificationsRoute;
  final String? messagesRoute;
  final String? chatThreadRoute;

  factory StaffRouteConfig.admin(String currentRoute) => StaffRouteConfig(
    role: UserRole.admin,
    currentRoute: currentRoute,
    destinations: StaffDestinations.admin(),
    profileRoute: RouteNames.adminProfile,
    notificationsRoute: RouteNames.adminNotifications,
    messagesRoute: RouteNames.adminMessages,
    chatThreadRoute: RouteNames.adminChatThread,
  );

  factory StaffRouteConfig.doctor(String currentRoute) => StaffRouteConfig(
    role: UserRole.doctor,
    currentRoute: currentRoute,
    destinations: StaffDestinations.doctor(),
    profileRoute: RouteNames.doctorProfile,
    notificationsRoute: RouteNames.doctorNotifications,
    messagesRoute: RouteNames.doctorMessages,
    chatThreadRoute: RouteNames.doctorChatThread,
  );

  factory StaffRouteConfig.assistant(String currentRoute) => StaffRouteConfig(
    role: UserRole.mcareAssistant,
    currentRoute: currentRoute,
    destinations: StaffDestinations.assistant(),
    profileRoute: RouteNames.assistantProfile,
    notificationsRoute: RouteNames.assistantNotifications,
    messagesRoute: RouteNames.assistantMessages,
    chatThreadRoute: RouteNames.assistantChatThread,
  );
}

/// Whether the current role may edit the global vital catalog.
bool canEditVitalCatalog(UserRole role) {
  if (role == UserRole.admin || role == UserRole.doctor) return true;
  return false; // assistants checked via AuthState.hasAssistantPermission
}
