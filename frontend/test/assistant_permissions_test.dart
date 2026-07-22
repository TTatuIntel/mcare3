import 'package:flutter_test/flutter_test.dart';

import 'package:mcare/shared/auth/auth_state.dart';
import 'package:mcare/shared/constants/route_names.dart';
import 'package:mcare/shared/dashboard/admin_workspace_catalog.dart';

void main() {
  group('AdminWorkspaceCatalog.forAssistantGrants', () {
    test('with no grants exposes only the always-on workspaces', () {
      final areas = AdminWorkspaceCatalog.forAssistantGrants((_) => false);
      final ids = areas.map((a) => a.id).toSet();

      // Delegated-only areas must stay hidden.
      expect(ids.contains('users'), isFalse);
      expect(ids.contains('approvals'), isFalse);
      expect(ids.contains('sos'), isFalse);

      // Always-available collaboration areas remain.
      expect(ids, containsAll(<String>{'support', 'alerts', 'messages'}));
    });

    test('granting canCreateUsers unlocks the users + patients areas', () {
      final areas = AdminWorkspaceCatalog.forAssistantGrants(
        (key) => key == AssistantPermissions.canCreateUsers,
      );
      final ids = areas.map((a) => a.id).toSet();

      expect(ids, containsAll(<String>{'users', 'patients'}));
      // A non-granted area stays hidden.
      expect(ids.contains('approvals'), isFalse);
    });

    test('grants are additive and never leak other permissions', () {
      final areas = AdminWorkspaceCatalog.forAssistantGrants(
        (key) => key == AssistantPermissions.canApproveHealthworkers,
      );
      final ids = areas.map((a) => a.id).toSet();

      expect(ids.contains('approvals'), isTrue);
      expect(ids.contains('users'), isFalse);
    });
  });

  group('AdminWorkspaceCatalog.assistantRouteFor', () {
    test('maps known admin areas to their assistant routes', () {
      expect(
        AdminWorkspaceCatalog.assistantRouteFor('users'),
        RouteNames.assistantUsers,
      );
      expect(
        AdminWorkspaceCatalog.assistantRouteFor('sos'),
        RouteNames.assistantSos,
      );
    });

    test('falls back to the assistant dashboard for unknown areas', () {
      expect(
        AdminWorkspaceCatalog.assistantRouteFor('does-not-exist'),
        RouteNames.assistantDashboard,
      );
    });
  });
}
