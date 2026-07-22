import 'package:flutter/material.dart';

import '../navigation/staff_route_config.dart';
import '../widgets/admin_screens/support_queue_screen.dart';
import '../widgets/staff_feature_views.dart';

/// Builds shared staff screens from [StaffRouteConfig] — use in `main.dart`
/// instead of per-role wrapper view files.
///
/// This factory only assembles the role-agnostic chrome (messages, threads,
/// generic notifications/profile, support). Role-specific screens (admin
/// notifications/profile/settings, doctor & assistant settings) are wired
/// directly in `main.dart`, which is the only layer allowed to depend on
/// individual role modules.
class StaffRouteFactory {
  StaffRouteFactory._();

  static Widget messages(StaffRouteConfig config) => StaffMessagesView(
        currentRoute: config.messagesRoute!,
        destinations: config.destinations.cast(),
        profileRoute: config.profileRoute,
        threadRouteName: config.chatThreadRoute!,
      );

  static Widget chatThread(StaffRouteConfig config, String conversationId) =>
      StaffChatThreadView(
        conversationId: conversationId,
        currentRoute: config.messagesRoute!,
        destinations: config.destinations.cast(),
        profileRoute: config.profileRoute,
      );

  static Widget notifications(StaffRouteConfig config) => StaffNotificationsView(
        currentRoute: config.notificationsRoute,
        destinations: config.destinations.cast(),
        profileRoute: config.profileRoute,
        notificationsRoute: config.notificationsRoute,
      );

  static Widget profile(StaffRouteConfig config) => StaffProfileView(
        currentRoute: config.profileRoute,
        destinations: config.destinations.cast(),
        notificationsRoute: config.notificationsRoute,
      );

  static Widget support(StaffRouteConfig config) => SupportQueueScreen(
        currentRoute: config.currentRoute,
        destinations: config.destinations,
        profileRoute: config.profileRoute,
        notificationsRoute: config.notificationsRoute,
      );
}
