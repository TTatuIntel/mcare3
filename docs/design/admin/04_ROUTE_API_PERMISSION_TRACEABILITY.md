# 04 — Route, API and Permission Traceability

## 1. Compatibility rule

The Guided Operations Hub is additive. No current named route, argument shape, controller endpoint, or server authorization check is removed in the first rollout.

Proposed canonical hub routes:

| Role | Home | Work | People | More |
|---|---|---|---|---|
| Admin | `/admin` | `/admin/work` | `/admin/people` | `/admin/more` |
| Assistant | `/assistant` | `/assistant/work` | `/assistant/people` | `/assistant/more` |

Existing message, detail, gate, and legacy list routes remain valid. A central registry maps them to the selected hub and filter.

## 2. Frontend legacy route mapping

### Admin

| Existing route | Guided parent | Initial state | Migration behavior |
|---|---|---|---|
| `/admin` | Home | Home | Feature-flagged legacy/new Home |
| `/admin/sos` | Work | Urgent → SOS | Preserve existing SOS argument parsing |
| `/admin/alerts` | Work | Urgent → Alerts | Preserve legacy screen until parity |
| `/admin/approvals` | Work | Requests → Approvals | Preserve legacy actions |
| `/admin/care-requests` | Work | Requests → Care | Preserve route/cancel |
| `/admin/assignments` | Work | Requests → Assignments | Preserve create/remove |
| `/admin/support` | Work | Messages → Support | Preserve ticket lifecycle |
| `/admin/messages` | Work | Messages → Conversations | Existing route remains bookmarkable |
| `/admin/messages/thread` | Work | Selected conversation | Preserve thread argument |
| `/admin/patients` | People | Patients | Preserve existing list during rollout |
| `/admin/users` | People | Staff | Preserve filters/create |
| `/admin/users/detail` | People | Selected staff | Preserve String ID argument/query form |
| `/admin/permissions` | People | Staff → Assistant → Access | Admin only |
| `/admin/vital-catalog` | More | Clinical setup | Preserve CRUD |
| `/admin/audit` | More | Insights → Audit | Preserve export |
| `/admin/analytics` | More | Insights → Analytics | Preserve KPI/timeseries |
| `/admin/security` | More | Insights → Security | Preserve canonical object action |
| `/admin/announcements` | More | Communication/content | Preserve CRUD/publish |
| `/admin/system` | More | Platform | Admin only |
| `/admin/settings` | More | Account/preferences | Preserve personal/platform links |
| `/admin/notifications` | Header bell | Notifications | Not a persistent tab |
| `/admin/profile` | Avatar/More | Account | Not a persistent tab |
| `/admin/complete-profile` | Gate | Complete profile | Outside hub |
| `/admin/force-password` | Gate | Change password | Outside hub |

### Assistant

Use the same parent mapping for the equivalent `/assistant/*` route. Visibility depends on current grants. Assistant has no System or permission-management screen. Complete-profile and force-password remain gates.

Existing assistant routes include patients, approvals, care requests, assignments, users/user detail, support, audit, analytics, alerts, messages/thread, notifications, SOS, vital catalog, announcements, security, settings, and profile.

## 3. Route registry requirements

Add a typed `StaffHubRouteRegistry` with:

- every admin and assistant route explicitly registered;
- role-specific canonical parent route;
- initial filter/type;
- supported argument parser;
- active-parent selection;
- capability predicate;
- safe fallback;
- an assertion/test that fails when a new staff route has no mapping.

Do not keep the current silent fallback pattern in `AdminWorkspaceCatalog.assistantRouteFor`, which can send unmapped analytics/messages/notification destinations back to the assistant dashboard.

### Active selection

Current `RoleShell` uses exact `destination.route == currentRoute`. The new shell must use `activeRoutes`, section ID, or registry resolution so `/admin/alerts` selects Work and `/admin/users/detail` selects People.

### Deep links

- Keep current named-route cases during the migration.
- Preserve SOS map/string arguments through `SosNavigation.parseArgs`.
- Preserve user-detail string ID and allowlisted `?id=` handling.
- Preserve conversation thread ID arguments.
- Normalize and allowlist query fields before use.
- Authenticate first, then verify role and capability, then restore the pending route.

Current hard-refresh/bookmark → login → original task restoration is not guaranteed. Do not claim support until a tested `PendingRoute`/`InitialRouteResolver` is added. Never accept an arbitrary return URL or cross-role path.

## 4. Backend route contract

All routes below are currently under:

```text
auth:sanctum
throttle:api-general
role:admin,mcare_assistant
prefix: /api/v1/admin
```

Admins bypass `permission:*`; assistants require the relevant DB-backed permission. The frontend gate is not part of the authorization decision.

### Session and Home

| Endpoint | Purpose | Current assistant rule | Guided use |
|---|---|---|---|
| `GET /admin/session` | Aggregated role-scoped snapshot | Controller conditionally includes buckets | Initial authorized snapshot; contract requires redaction/atomic apply |
| `GET /admin/analytics/kpis` | KPI values | `can_view_activity_logs` | More → Analytics; Home only if authorized |
| `GET /admin/analytics/timeseries` | Trends | `can_view_activity_logs` | More → Analytics |

The current Home separately calls KPI even after session hydration. Guided Home should define one authoritative snapshot and never use hard-coded KPI fallbacks.

### Urgent work

| Endpoint | Command | Current rule |
|---|---|---|
| `GET /admin/alerts` | List system-wide alerts | Baseline admin/assistant route today |
| `PATCH /admin/alerts/{alert}/acknowledge` | Acknowledge alert | Baseline today |
| `PATCH /admin/alerts/{alert}/resolve` | Resolve with action/note | Baseline today |
| `GET /admin/sos-events` | List SOS | `can_access_emergency_location` |
| `PATCH /admin/sos-events/{event}` | Resolve/respond SOS | `can_access_emergency_location` |

The generic alert feed currently includes some SOS-kind notification data. Guided Work must not treat it as the canonical SOS or expose location/actions without the SOS capability. Server hardening should remove/redact this crossover.

### Requests

| Endpoint | Command | Assistant permission |
|---|---|---|
| `GET /admin/approvals` | List worker approvals | `can_approve_healthworkers` |
| `PATCH /admin/approvals/{user}/approve` | Approve | `can_approve_healthworkers` |
| `PATCH /admin/approvals/{user}/reject` | Reject | `can_approve_healthworkers` |
| `POST /admin/approvals/{user}/request-info` | Request information | `can_approve_healthworkers` |
| `POST /admin/approvals/{user}/credential` | Upload credential | `can_approve_healthworkers` |
| `GET /admin/approvals/{user}/credential/stream` | Stream credential | `can_approve_healthworkers` |
| `GET /admin/care-requests` | List | `can_manage_care_requests` |
| `PATCH /admin/care-requests/{id}/route` | Route | `can_manage_care_requests` |
| `PATCH /admin/care-requests/{id}/cancel` | Cancel | `can_manage_care_requests` |
| `GET /admin/assignments` | List | `can_assign_patients` |
| `POST /admin/assignments` | Create | `can_assign_patients` |
| `DELETE /admin/assignments/{id}` | Remove | `can_assign_patients` |

### Support and conversations

| Endpoint family | Commands | Current assistant rule |
|---|---|---|
| `/admin/support-tickets` | List, reply, assign, resolve, close, reopen | Baseline today; proposed finer assigned/all/reply/assign capabilities |
| `/admin/conversations` | List, create, thread, send, mark read | Baseline today; proposed direct/oversight abilities |
| `/admin/notifications` | List, read, resolve, read all | Baseline personal/staff feed |

Resolving a notification must not resolve its underlying clinical task.

### People

| Endpoint | Command | Current assistant permission |
|---|---|---|
| `GET /admin/users` | Directory | `can_create_users` |
| `POST /admin/users` | Create | Route requires `can_create_users`; controller also checks elevated-role grants |
| `GET /admin/patients/{patient}` | Read clinical profile | `can_create_users` today |
| `PATCH /admin/users/{user}/status` | Status | `can_create_users` today |
| `POST /admin/users/{user}/password-reset` | Reset | `can_create_users` today |
| `POST /admin/users/{user}/unlock` | Unlock | `can_create_users` today |
| `POST /admin/users/{user}/resend-invite` | Resend invite | `can_create_users` today |
| `PATCH /admin/users/{user}/role` | Change role | `can_change_user_types`; controller checks privileged targets |
| `GET/PATCH /admin/permissions/*` | Manage assistant grants | `role:admin` only |

The current coarse `can_create_users` scope is a security-hardening target. The UI must not normalize this breadth as the desired future authorization model.

### More

| Endpoint family | Purpose | Current assistant permission |
|---|---|---|
| `/admin/audit`, `/admin/audit/export` | Audit/read/export | `can_view_activity_logs` |
| `/admin/security-incidents` | List/resolve | `can_view_security_incidents` |
| `/admin/announcements` | CRUD/publish | `can_manage_advertising` |
| `/admin/vital-catalog` | CRUD | `can_manage_vital_catalog` |
| `/admin/system/settings` | Read/update | `role:admin` only |

## 5. Current permission keys

| Key | Current purpose |
|---|---|
| `can_approve_healthworkers` | Worker approvals |
| `can_manage_care_requests` | Care request routing/cancel |
| `can_assign_patients` | Assignments |
| `can_create_users` | Broad users/patient profile/status/reset scope today |
| `can_change_user_types` | Role changes |
| `can_register_admin` | Create/promote admin, controller-enforced |
| `can_register_assistant` | Create/promote assistant, controller-enforced |
| `can_view_activity_logs` | Audit and analytics |
| `can_view_security_incidents` | Security incidents |
| `can_access_emergency_location` | SOS/location |
| `can_manage_advertising` | Announcements |
| `can_manage_vital_catalog` | Vital catalog |

The security roadmap replaces coarse keys with explicit capabilities while keeping a compatibility mapper during migration.

## 6. New additive session contract

Recommended additions, versioned and backward compatible:

```json
{
  "capabilities": ["alerts.view", "alerts.acknowledge"],
  "capability_version": 42,
  "session_expires_at": "...",
  "ui_flags": {
    "guided_operations_hub": true
  },
  "work_summary": {
    "counts": {},
    "items": []
  }
}
```

Rules:

- Return only the signed-in role's resolved hub flag.
- Unauthorized fields are absent/null, not misleading zeroes.
- Work summaries are redacted and limited to 3–5 items.
- Each item carries `type`, `state_version`, and `allowed_actions`.
- Detail is fetched only after deliberate, authorized open.
- Keep the current `/admin/session` fields until legacy clients age out.

## 7. Guard correction required

Current `/admin/sos` frontend wiring uses a guard that admits both admin and assistant into the admin namespace. Backend middleware still protects data, but the route should use the admin-only frontend guard. Assistants must use `/assistant/sos` plus their permission gate.

This is defense in depth and route hygiene; it does not replace server authorization.

## 8. Permission revocation sequence

1. Refresh canonical capabilities before session data.
2. Detect capability-version change.
3. Cancel in-flight restricted detail requests.
4. Remove restricted data from state, selection, semantics, and navigation.
5. Select the first safe Work filter or Home.
6. Show `Your access was updated.`
7. Server continues returning 403 for any stale request.

## 9. Traceability test gate

- Every constant in the admin/assistant route groups maps to exactly one parent/gate.
- Every existing route resolves with the feature flag off and on.
- Each API family has admin, exact-grant assistant, missing-grant assistant, wrong-role, and unauthenticated tests.
- Each typed Work command reaches the correct canonical endpoint.
- No SOS notification action can resolve the underlying SOS accidentally.
- No direct route reveals data before the server capability check.

