// ---------------------------------------------------------------------------
// PAGE REMOVED — merged into the care-requests workspace.
//
// "Assignments" and "Care requests" were two views of one workflow: a patient
// requests a provider, staff approve / re-route / decline, and an approval is
// what creates the care assignment. Both now live on a single admin screen
// (`admin/care_requests/admin_care_requests_view.dart`) with an Assignments
// tab.
//
// The `/admin/assignments` and `/assistant/assignments` routes are kept alive
// so bookmarks, notification deep links, and older builds keep working — they
// redirect to the merged screen opened on the Assignments tab. Nothing new
// should point here.
// ---------------------------------------------------------------------------

import 'package:flutter/material.dart';

import '../../shared/constants/route_names.dart';
import '../../shared/navigation/staff_destinations.dart';
import '../care_requests/admin_care_requests_view.dart';

export '../care_requests/admin_care_requests_view.dart' show CareTab;

/// Redirect target for the retired `/admin/assignments` route.
class AdminAssignmentsView extends StatelessWidget {
  const AdminAssignmentsView({super.key});

  @override
  Widget build(BuildContext context) => const MergedAssignmentsRedirect(
        target: RouteNames.adminCareRequests,
        currentRoute: RouteNames.adminAssignments,
        profileRoute: RouteNames.adminProfile,
        notificationsRoute: RouteNames.adminNotifications,
      );
}

/// Renders the merged workspace on its Assignments tab, then swaps the route
/// so the address bar and back stack settle on the surviving page.
class MergedAssignmentsRedirect extends StatefulWidget {
  const MergedAssignmentsRedirect({
    super.key,
    required this.target,
    required this.currentRoute,
    required this.profileRoute,
    required this.notificationsRoute,
    this.canAssign = true,
    this.canTriage = true,
  });

  /// Route that replaces this one — the merged care-requests page.
  final String target;

  final String currentRoute;
  final String profileRoute;
  final String notificationsRoute;
  final bool canAssign;
  final bool canTriage;

  @override
  State<MergedAssignmentsRedirect> createState() =>
      _MergedAssignmentsRedirectState();
}

class _MergedAssignmentsRedirectState extends State<MergedAssignmentsRedirect> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(widget.target);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Shown for a single frame — identical content to the redirect target, so
    // the swap is invisible even on a slow first paint.
    final assistant = widget.currentRoute == RouteNames.assistantAssignments;
    return CareRequestsScreen(
      currentRoute: widget.currentRoute,
      destinations: assistant
          ? StaffDestinations.assistant()
          : StaffDestinations.admin(),
      profileRoute: widget.profileRoute,
      notificationsRoute: widget.notificationsRoute,
      canAssign: widget.canAssign,
      canTriage: widget.canTriage,
      initialTab: CareTab.assignments,
    );
  }
}

/// Deprecated alias kept so the `shared/widgets/admin_screens` export chain and
/// any older call site still resolve. Use [CareRequestsScreen] instead.
@Deprecated(
  'Assignments merged into CareRequestsScreen. '
  'Use CareRequestsScreen(initialTab: CareTab.assignments).',
)
class AssignmentsScreen extends StatelessWidget {
  const AssignmentsScreen({
    super.key,
    required this.currentRoute,
    required this.destinations,
    required this.profileRoute,
    required this.notificationsRoute,
    this.canAssign = true,
  });

  final String currentRoute;
  final List destinations;
  final String profileRoute;
  final String notificationsRoute;
  final bool canAssign;

  @override
  Widget build(BuildContext context) => CareRequestsScreen(
        currentRoute: currentRoute,
        destinations: destinations,
        profileRoute: profileRoute,
        notificationsRoute: notificationsRoute,
        canAssign: canAssign,
        initialTab: CareTab.assignments,
      );
}
