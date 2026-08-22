# 06 — Implementation, Migration and Test Plan

## 1. Delivery strategy

The redesign is an additive, feature-flagged evolution of the current Flutter/Laravel application. It does not begin by deleting routes, replacing state, or rewriting working backend flows.

### Order of safety

1. Record current behavior and add missing regression/security tests.
2. Resolve P0 backend/session/privacy risks.
3. Add route grouping and shared presentation models with flags off.
4. Build shared Guided views that initially link to existing actions/screens.
5. Add typed inline detail/actions one workflow at a time.
6. Enable internal Admin, then Assistant, then broader cohorts.
7. Retain the legacy experience for rollback through at least one complete mobile release after full rollout.

## 2. No-duplication architecture rules

| Rule | Enforcement |
|---|---|
| One Home implementation | `GuidedHomeView` receives role/config/capabilities; no admin and assistant copies |
| One Work model/ranker | `StaffWorkItem` + `StaffWorkItemComposer` normalize authorized sources once |
| One People implementation | Role-aware `StaffPeopleView`; contextual capabilities control actions |
| One More catalog | Typed section registry with capability predicates |
| One route map | `StaffHubRouteRegistry` owns legacy → hub mapping and active selection |
| One command path | Widgets call controller/state command interfaces; no direct HTTP in cards |
| One server authority | Laravel middleware/policies/allowed actions; UI gates only improve UX |
| One responsive component | LayoutBuilder/reflow; no `mobile_*` and `web_*` business implementations |
| One status vocabulary | Semantic tokens and shared labels for critical/warning/success/info |
| One source of counts | Authorized snapshot/work composer; no separate hero/KPI/attention calculations |

Code review should reject duplicated role widgets, repeated route switches, screen-local API calls, or independent work ranking.

## 3. Proposed frontend additions

```text
frontend/lib/shared/staff_hub/
├── models/
│   ├── staff_hub_section.dart
│   ├── staff_dashboard_snapshot.dart
│   └── staff_work_item.dart
├── navigation/
│   ├── staff_hub_route_registry.dart
│   └── staff_hub_route_args.dart
├── services/
│   ├── staff_dashboard_snapshot_builder.dart
│   └── staff_work_item_composer.dart
├── state/
│   └── staff_hub_controller.dart
├── views/
│   ├── guided_home_view.dart
│   ├── staff_work_view.dart
│   ├── staff_people_view.dart
│   └── staff_more_view.dart
└── widgets/
    ├── adaptive_staff_header.dart
    ├── adaptive_detail_host.dart
    ├── goal_card.dart
    ├── staff_surface_card.dart
    ├── sync_status_chip.dart
    └── work_item_tile.dart

frontend/lib/shared/state/ui_feature_flags.dart
```

Potential phase-later adapter:

```text
frontend/lib/shared/navigation/legacy_staff_hub_entry.dart
```

## 4. Existing frontend touchpoints

| File/area | Intended change | Risk control |
|---|---|---|
| `route_names.dart` | Add admin/assistant Work, People, More routes | Never rename existing constants |
| `main.dart` | Wire new routes and correct admin SOS frontend guard | Keep all current cases; route tests |
| `staff_destinations.dart` | Admin/assistant expose four grouped sections | Doctor list unchanged |
| `role_nav_destination.dart` | Add parent/active route semantics or introduce separate typed section | Backward-compatible fields |
| `role_shell.dart` | Compact/extended rail, grouped active selection, adaptive header | Opt-in flag/config; golden tests |
| `responsive.dart` | Reuse current breakpoints; expose wide/local helpers if needed | Layout-only branching |
| `navigation_roots.dart` | New hubs are roots; details are drill-down | Back-stack regression tests |
| `staff_route_config.dart` | Replace `List<dynamic>` with a typed collection | Compile-time migration |
| `admin_workspace_catalog.dart` | Explicit role-aware mappings; remove silent unknown fallback | Exhaustive mapping test |
| `admin_session_service.dart` | Atomic snapshot hydrate, freshness/errors, capability purge | Do not clear good state before fetch |
| Admin/assistant dashboard wiring | Point to shared Home when role flag is on | Legacy view retained |
| Existing state mutations | Expose typed controller calls where needed | Do not reimplement API logic |

Avoid a global `GlassCard` or `AppTheme` rewrite in the first hub change because those are shared with patient, doctor, authentication, and external portal experiences.

## 5. Backend additions and hardening

### 5.1 Pre-cutover security patch

Complete the P0 items in the security blueprint, prioritizing:

- production-disable mock OAuth;
- account-state and session-version middleware;
- immediate token invalidation;
- endpoint-specific auth limiters and reset expiry;
- target hierarchy for privileged user actions;
- SOS recipient/data filtering;
- private medical file storage/delivery;
- generic push text and PHI minimization.

### 5.2 Additive session contract

Add, without removing old fields:

- canonical `capabilities`;
- `capability_version`;
- `session_expires_at`;
- role-resolved UI flag;
- redacted authorized counts/task summaries;
- `allowed_actions` and `state_version` for work items.

An optional `GET /admin/work-summary` is preferred once implemented. The first flagged UI can compose existing permission-scoped state while the contract is developed.

### 5.3 Runtime flags

Use two independent DB-backed settings:

- `guided_admin_hub_enabled`
- `guided_assistant_hub_enabled`

Add them through a migration as disabled defaults and also update seeders for new installations. `/admin/session` returns only the current user's resolved boolean:

```json
"ui_flags": { "guided_operations_hub": false }
```

Frontend defaults to false when missing, unauthorized, malformed, or unavailable. Feature flags never authorize data/actions.

### 5.4 Typed commands

Keep existing endpoints during migration. Add idempotency/version support incrementally. Every server work summary specifies the exact allowed typed actions. Unknown command/type returns a safe validation error.

## 6. Phased plan

### Phase 0 — Freeze and baseline

Deliverables:

- Export route inventory and API response fixtures.
- Record current screenshots/goldens at supported sizes.
- Run/record `flutter analyze`, existing Flutter tests, backend tests, and route list.
- Add tests around current behavior before changing navigation.
- Resolve/triage dirty-worktree overlap before editing.

Exit gate:

- Baseline failures understood and documented.
- Every current admin/assistant route has an owner and expected outcome.

### Phase 1 — Security foundation

Deliverables:

- P0 auth/account/session controls.
- RBAC/IDOR route matrix.
- SOS/push/file privacy fixes.
- Global auth-failure cleanup design.
- Feature-flag migration disabled.

Exit gate:

- No unresolved SEC-P0 without formal exception.
- Security test matrix green.

### Phase 2 — Typed IA and route compatibility

Deliverables:

- `StaffHubRouteRegistry` and exhaustive tests.
- New canonical hub routes.
- Four-section destination configuration behind flags.
- Parent-selection and back-stack support.
- Correct `/admin/sos` frontend guard.

Exit gate:

- Every legacy route works flag off/on.
- No assistant route reaches data/action without server permission.

### Phase 3 — Shared shell and design components

Deliverables:

- Opt-in Guided `RoleShell` configuration.
- Bottom bar, compact rail, extended rail.
- Staff surface, header, goal card, sync status, adaptive detail host.
- Responsive, keyboard, semantics, dark-mode tests.

Exit gate:

- No overflow at viewport/text matrix.
- Doctor/patient shells unchanged.

### Phase 4 — Guided Home

Deliverables:

- Shared authorized dashboard snapshot.
- Goal cards and ranked next-action previews.
- Honest freshness/health state.
- Remove duplicate hero/KPI/attention calculations only after parity.

Exit gate:

- One underlying event appears once.
- Unknown/unauthorized metrics never render as fabricated zero/trend.

### Phase 5 — Work read-only aggregation

Deliverables:

- `StaffWorkItem` and composer.
- Filters, sorting, deduplication, ranking, redaction.
- Rows open existing legacy detail/screens; no new inline mutations yet.

Exit gate:

- Full task inventory parity.
- SOS is canonical and separate from notifications.
- Zero/partial/all-grant assistant matrices green.

### Phase 6 — Typed Work detail and actions

Migrate one type at a time:

1. Support
2. Approvals
3. Care requests and assignments
4. Alerts acknowledge
5. Alert resolution
6. SOS last, after privacy/concurrency hardening
7. Conversations

For each type:

- reuse existing state/API mutation;
- define allowed actions;
- add pending/double-submit/failure/conflict handling;
- add audit assertion;
- compare legacy/new outcomes.

Exit gate:

- Typed command contract tests and parity evidence per task type.

### Phase 7 — People

Deliverables:

- Shared patient/staff directory.
- Server search/pagination.
- Contextual patient/staff detail.
- Admin-only Assistant Access.
- Target hierarchy and step-up for sensitive actions.

Exit gate:

- No PHI in generic rows/search telemetry.
- Role/status/reset/permission matrix green.

### Phase 8 — More and account integration

Deliverables:

- Group Insights, Communication/content, Clinical setup, Platform, Account.
- Preserve all existing screens/routes.
- Add recent-auth/MFA/confirmation requirements to sensitive settings.

Exit gate:

- No platform/clinical control is exposed by role or stale state.

### Phase 9 — Controlled rollout

1. Staging with both flags off.
2. Internal admin cohort on.
3. All admins on after parity/telemetry.
4. Selected assistants with exact permission scenarios.
5. All assistants after security/accessibility sign-off.
6. Web, Android, iOS, and Windows verification.

### Phase 10 — Cleanup

Only after one complete mobile release at 100% and a rollback-free observation period:

- route legacy list paths through compatibility adapters if desired;
- remove duplicated dashboard-only builders proven unused;
- deprecate bulk PHI session buckets after old clients age out;
- retain legacy route constants/detail argument compatibility.

No destructive database cleanup is combined with the UI cutover.

## 7. Rollback

Immediate role-specific rollback:

- Set `guided_admin_hub_enabled=false` or `guided_assistant_hub_enabled=false`.
- Next session refresh/restoration renders the legacy experience.
- Existing routes, APIs, state, and database remain compatible.
- No app-store release or database rollback is required.

If the new session additions fail, clients default flag false. If a new schema field causes runtime errors, deploy additive code rollback; do not drop columns until all clients are known safe.

## 8. Test plan

### 8.1 Static and unit

- `flutter analyze`
- Route registry exhaustiveness
- Permission/capability mapping
- Work stable IDs, redaction, deduplication and comparator
- Snapshot authorization and unknown/null handling
- Badge/count rules
- Typed allowed-action mapping

### 8.2 Widget and golden

Viewports: 360×800, 390×844, 599×900, 600×960, 800×1024, 1024×768, 1440×900, 1920×1080.

Scenarios:

- Admin and zero/partial/all-grant assistant
- Light/dark
- 100% and 200% text
- Loading, empty, offline, stale, 401, 403, 409, 500
- Keyboard focus/activation and reduced motion
- No overflow/truncation and one selected parent

### 8.3 Navigation

- Every existing admin/assistant route, flag off/on
- Deep-link arguments/query for SOS, user detail, conversation thread
- Back stack from detail → hub → prior safe context
- Hard refresh and authenticated pending-route restoration, once implemented
- Notification and SOS overlay navigation
- Permission revoked while filter/detail/action is open

### 8.4 Backend contract and authorization

For each route group:

- unauthenticated 401;
- patient/doctor 403 where inappropriate;
- zero-grant assistant 403/redacted;
- exact-grant assistant expected success;
- admin expected success;
- cross-target ID 404/403 with no side effect;
- admin-only permissions/System;
- sensitive mutation emits audit.

### 8.5 Mutation behavior

- Success
- Validation failure
- Network/server failure
- Double tap/replay
- Idempotency retry
- Stale state/version conflict
- Permission revoked during request
- Correct optimistic rollback; no optimistic clinical completion

### 8.6 Security/privacy

- All tests specified in `05_SECURITY_PRIVACY_SAFETY.md`
- No PHI in push, URL, logs, telemetry or browser cache
- Private file/credential authorization and scan flow
- Token/session expiration, rotation and revocation

### 8.7 Performance

- No eager full-directory render
- Pagination and list virtualization
- No duplicate poll/KPI fetch
- Smooth scroll at representative queue size
- Measured first content and refresh behavior on mid-range Android/web

### 8.8 Manual clinical/operational validation

- Admin handles alert, SOS, approval, care request, assignment, support and conversation.
- Partial-grant assistant completes only authorized flows.
- Permission grant/revoke is visible within expected refresh and server blocks immediately.
- Product/clinical owner validates status wording and command consequence.

## 9. Observability

Track without PHI:

- flag cohort/version;
- hub load/refresh error rate;
- 401/403/409/5xx by endpoint/type;
- task action start/success/failure by type;
- time to first action;
- route fallback/unknown registry event;
- layout overflow assertion in nonproduction;
- permission-version changes;
- rollback activation.

Alerts should trigger for authorization spikes, queue mapping errors, session refresh failures, typed-command mismatch, or audit-write failure.

## 10. Definition of done

The redesign is complete only when:

- all four hubs are shared across admin/assistant;
- every legacy capability is traceable and reachable when authorized;
- every legacy route still resolves;
- no duplicate Home/work ranking logic remains in active code;
- typed commands reach canonical endpoints and are audited;
- P0 security gates are closed;
- responsive/accessibility/security/regression suites pass;
- production-like migration and rollback are rehearsed;
- admin and assistant owner acceptance is recorded;
- legacy removal, if any, waits for the agreed compatibility period.

## 11. Explicitly prohibited shortcuts

- Deleting old routes to force adoption
- Copying Admin views into Assistant folders
- Adding direct `AdminApi` calls inside new UI cards
- Treating hidden controls as authorization
- Representing unauthorized counts as zero
- Generic resolve for SOS/alert/notification/security
- Storing web production bearer tokens in localStorage
- Shipping `Systems online` without a real health contract
- Combining security fixes with destructive data migration
- Enabling all users without role-specific kill switches

