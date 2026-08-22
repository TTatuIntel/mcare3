# Safe Implementation Roadmap - Administrator First

## Delivery strategy

The Administrator is the first visual pilot, but only after baseline and P0 security work. The new UI is additive, disabled by default and linked to existing detail screens before any mutation is moved. The same shared components then serve Assistant, Patient and Doctor without cloned role implementations.

## Non-breaking constraints

- Preserve all 99 named routes and their current argument shapes.
- Preserve existing Laravel endpoints during the compatibility period.
- Preserve existing state stores and mutation methods as canonical.
- Do not globally restyle shared legacy components in the first pass.
- Do not combine clinical commands into a generic resolve operation.
- Do not change authorization through navigation or feature flags.
- Retain legacy screens for immediate rollback.
- Isolate every role rollout behind an independent server-resolved flag.

## Phase 0 - freeze, inventory and baseline

1. Resolve ownership of overlapping dirty-worktree changes before editing shared files.
2. Export the 99-route manifest, 171-route API inventory and response-contract fixtures.
3. Capture current screenshots at compact, medium and expanded sizes.
4. Add route/deep-link/back-stack tests around every role.
5. Add backend role, account-state, permission and IDOR matrices.
6. Add baseline performance and accessibility measurements.
7. Record current API payload and mutation side effects.

Exit: legacy behavior is reproducible and a regression can be detected.

## Phase 1 - P0 backend and session safety

1. Disable mock OAuth outside local/testing.
2. Enforce account state and auth version on protected APIs and broadcast auth.
3. Correct endpoint-specific throttles and recovery expiry/single-use.
4. Revoke sessions on suspension, password, role and privilege changes.
5. Filter SOS, alerts, support and messages by explicit authority and minimum necessary data.
6. Move medical files to private delivery and introduce scanning policy.
7. Add global client 401/403 handling and secure session adapters.

Exit: zero open P0 findings required for production enablement.

## Phase 2 - additive Design System v2

Build opt-in components and tests:

- plain staff surface;
- adaptive page header;
- four-destination shell;
- constraint-based grid;
- work-item row;
- filter/status chips;
- adaptive detail pane;
- freshness/offline banner;
- standardized loading, empty, error, conflict and receipt states.

No legacy screen changes its appearance in this phase.

## Phase 3 - route registry and feature flags

1. Add a typed route-to-parent registry.
2. Add new hub entry routes without removing old routes.
3. Add independent Admin and Assistant flags, default false.
4. Add parent selection for every current child route.
5. Add safe handling for permission revocation and missing route arguments.
6. Prove flag-off behavior is byte-for-byte/routing equivalent where practical.

## Phase 4 - Administrator Guided Home

Build shared Home from current authorized stores:

- truthful freshness;
- urgent count;
- three recommended next actions;
- privacy-minimized counts;
- links into existing details.

Do not show unsupported system health, fabricated trends or hard-coded response time. Internal Admin cohort only after accessibility/golden and contract tests pass.

## Phase 5 - Administrator Work

### 5A read-only aggregation

Compose a typed list from current alert, SOS, approval, care request, assignment and support state. Deduplicate and rank once. Filters route to existing details. No new inline mutation yet.

### 5B typed actions, one workflow at a time

Recommended order:

1. Support replies and state changes.
2. Approvals with credential checks and reasons.
3. Care requests and assignments.
4. Alert acknowledgement.
5. Alert resolution with action/note.
6. SOS last, after recipient, location and state-machine hardening.

Every command gets error, duplicate-submit, conflict, audit and rollback tests before the next command type migrates.

## Phase 6 - Administrator People and More

People uses Patients/Staff segmentation and contextual detail. Care-team assignment lives inside patient detail. Staff status, invite, unlock and role actions live in staff detail with explicit hierarchy. Assistant grant management is Admin-only.

More groups analytics/audit/security, announcements/vital catalog, system settings and account links. Unsupported billing, lab, pharmacy, backup, integration or API-secret screens are not added.

## Phase 7 - delegated Assistant

The Assistant consumes the same Home, Work, People and More implementations with role route config and live capabilities. It receives no copied dashboard, queue or person-detail business logic.

Run a full matrix for zero grants, each individual grant, valid combinations, grant revocation during an open detail and privilege-target restrictions. Enable through its separate flag only after Admin stabilizes.

## Phase 8 - shared auth/account consistency

Migrate auth shell, form fields, validation, profile, password and settings presentation after session hardening. Keep route and API contracts. Staff invite/approval and patient self-registration remain distinct.

## Phase 9 - Patient

Add Patient Home/Health/Care/More hubs behind a patient flag. Migrate page families in this order:

1. Read-only Home aggregations.
2. Vitals and trends.
3. Medications and dose logging.
4. Documents.
5. Appointments.
6. Messages and care team.
7. Profile/settings/support.
8. SOS and external link management last.

Existing detail screens and sheets remain the initial mutation path.

## Phase 10 - Doctor

1. Read-only Home and Work from `/doctor/session`.
2. Assigned Patients directory.
3. Group the 13 patient-workspace sections into five visual families.
4. Migrate appointments, reports, prescriptions, document and message actions one at a time.
5. SOS/alert resolution last.
6. Do not display patient-specific thresholds as saved until a persistence endpoint exists.

## Phase 11 - External Clinical Access

Complete token, portal-session, scope, audit and file hardening first. Then replace the long page with access gate, one-patient review tabs, typed Add finding stepper, receipt and terminal states. Enable behind `external_workspace_v2_enabled`.

## Phase 12 - future backend products

Structured lab/imaging, billing/payments/insurance, pharmacy inventory, referrals, embedded video, AI and privileged infrastructure controls are separate discovery, security, data-model, API and implementation projects. They do not ship as empty menu items.

## Suggested shared frontend touchpoints

| Area | Safe approach |
|---|---|
| Routes | Add constants/cases and registry; keep Navigator 1 |
| `RoleShell` | Opt-in v2 behavior for selected roles; do not break Doctor legacy during Admin pilot |
| Staff destinations | Return four typed parent sections; child catalogue stays permission-filtered |
| Grids | Local `LayoutBuilder` and min tile width |
| Lists | Own scrolling with `ListView.builder`/slivers |
| Dashboard data | One permission-aware snapshot adapter |
| Work data | One typed composer delegating to existing state mutations |
| Theme | Add component variants; avoid global restyle first |
| Sessions | Atomic hydrate and last-known freshness; centralized auth failure |

## Rollout and rollback

1. Developer/internal flag on.
2. Admin test cohort.
3. Wider Admin cohort with telemetry that excludes PHI.
4. Admin full rollout and rollback rehearsal.
5. Assistant grant-matrix cohort.
6. Patient and Doctor independent pilots.
7. External last.

Rollback flips only the affected role flag to false. It does not require a database rollback or route deletion. Destructive migrations are prohibited in the compatibility window.

## Definition of done for each screen family

- Visual spec approved.
- Route and argument compatibility proven.
- Backend authorization and IDOR matrix green.
- Existing mutation side effects preserved.
- Loading/empty/offline/error/permission/conflict/success states implemented.
- Compact/medium/expanded/wide and 200 percent text tests green.
- Keyboard and screen-reader checks green.
- No PHI in telemetry, URLs or unintended caches.
- Feature-flag rollback proven.
- UAT acceptance signed by the relevant role owner.

## First Administrator implementation work package

This is the first package to begin after blueprint approval. It is deliberately additive and contains no production cutover.

| Deliverable | Included work | Explicit non-goal | Exit evidence |
|---|---|---|---|
| Baseline manifest | Freeze routes, arguments, API fixtures, screenshots and current side effects | No route rename or UI replacement | Route/API inventory and legacy smoke suite |
| Security patch set | Close mock OAuth, account-state, session-revocation, SOS-recipient and private-file P0s | No visual feature flag enabled | Security matrix and migration rehearsal |
| Design System v2 foundation | Add staff surface, header, chips, work row, detail pane, constraint grid and state views | No global `AppTheme`/`GlassCard` restyle | Widget, semantics, dark and 200 percent text tests |
| Route registry | Map all Admin/Assistant legacy routes to Home/Work/People/More | No legacy constant deletion | Registry completeness and selected-parent tests |
| Flag infrastructure | Add independent Admin/Assistant server-resolved flags defaulting false | Flag is never authorization | Flag-off parity and immediate rollback tests |
| Guided Admin Home | Read-only, privacy-minimized snapshot and links to current details | No inline clinical mutation | Internal cohort UAT and truthful freshness checks |

Only after these six deliverables pass may the read-only Administrator Work composer begin. People, More and inline actions follow the phase order above.
