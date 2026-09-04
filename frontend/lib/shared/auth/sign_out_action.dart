import 'package:flutter/material.dart';

import '../constants/route_names.dart';
import '../navigation/root_navigator.dart';
import '../widgets/app_dialog.dart';
import '../widgets/app_icons.dart';
import 'auth_state.dart';

/// Uses the same confirmation and cleanup flow from every sign-out entry.
Future<void> confirmAndSignOut(BuildContext context) async {
  final ok = await AppDialog.confirm(
    context,
    title: 'Sign out?',
    message:
        'You\'ll be returned to the home screen and will need to sign in again.',
    danger: true,
    icon: AppIcons.logout,
    iconActionOnly: true,
  );
  if (ok != true) return;
  AuthState.instance.signOut();
  rootNavigatorKey.currentState?.pushNamedAndRemoveUntil(
    RouteNames.landing,
    (_) => false,
  );
}
