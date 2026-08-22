# mCare — Remote Patient Monitoring Platform

**mCare** is a full-stack Remote Patient Monitoring (RPM) and healthcare-management platform. Patients record vitals at home; the Laravel backend evaluates readings against clinical thresholds; care teams respond through alerts, messaging, appointments, prescriptions, reports, documents, and emergency SOS workflows.

**Stack:** Laravel 12 REST API (`backend/`) · Flutter 3 (`frontend/`, web + Android + iOS + Windows) · MySQL 8+

**Repository truth last verified:** 2026-08-07

> **Canonical documentation:** this root `README.md` is the single engineering, product, setup, deployment, and rollout reference. The approved screen-by-screen visual specification is the [complete mCare design blueprint PDF](output/pdf/mcare-complete-application-design-blueprint.pdf).
>
> **Golden rule:** one application, one design language, one shared component library, and one backend contract. Roles change content, accent, navigation context, and authority—not component ownership.

---

## Contents

1. [Product truth](#1-product-truth)
2. [Verified repository snapshot](#2-verified-repository-snapshot)
3. [Quick start](#3-quick-start)
4. [Architecture](#4-architecture)
5. [Approved design system](#5-approved-design-system)
6. [Navigation and responsive structure](#6-navigation-and-responsive-structure)
7. [Role experiences and capabilities](#7-role-experiences-and-capabilities)
8. [External Clinical Access](#8-external-clinical-access)
9. [Backend and API compatibility](#9-backend-and-api-compatibility)
10. [Security and production gates](#10-security-and-production-gates)
11. [Safe implementation and old-design retirement](#11-safe-implementation-and-old-design-retirement)
12. [Testing, UAT, and rollback](#12-testing-uat-and-rollback)
13. [Environment and configuration](#13-environment-and-configuration)
14. [Deployment](#14-deployment)
15. [Google Play and Apple App Store](#15-google-play-and-apple-app-store)
16. [Demo accounts](#16-demo-accounts)
17. [Documentation policy](#17-documentation-policy)
18. [License](#18-license)

---

## 1. Product truth

mCare supports five distinct experiences from one Flutter application:

| Experience | Identity and scope |
|---|---|
| Patient | Registered user; owns their chart and care workflows |
| Doctor | Registered clinician; works only within an assigned caseload |
| Administrator | Registered platform operator with administrative authority |
| mCare Assistant | Registered **human delegated staff member** with permission-scoped administrative access |
| External clinician | Time-limited **token guest** invited by one patient to one patient record; not an account role |

### Terminology that must not change

- **mCare Assistant is a person.** The current `mcare_assistant` role is not an AI chatbot, voice assistant, clinical decision-support system, or automation agent.
- **External Clinical Access is token-based.** An outside clinician does not receive a persistent account, caseload, inbox, settings area, or patient switcher.
- **Patient onboarding is the patient profile-completion flow.** Staff-only complete-profile routes are separate account gates.
- **mCare is a monitoring and care-coordination product.** It must not claim to diagnose, replace professional clinical judgment, or replace emergency services.

### Existing functional domains

The repository currently contains working domains for:

- authentication, registration, verification, password recovery, OTP, invitations, and account/profile management;
- users, health profiles, roles, assistant grants, approvals, and assignments;
- vital catalog, tracked vitals, readings, thresholds, alerts, and patient report requests;
- medications, dose tracking, prescriptions, appointments, and meal plans;
- medical documents, conversations, messages, notifications, and support tickets;
- patient care-team requests and clinician caseloads;
- emergency SOS, announcements, security incidents, audit events, analytics, and settings;
- patient-issued external-access links/codes, consultation notes, vitals, medications, and document uploads;
- FCM token registration and an opt-in Laravel Reverb vital-alert channel.

### Not complete backend modules

Do not present the following concepts as functional product modules until their own models, policies, API contracts, tests, and operational controls exist:

- structured laboratory ordering/results;
- structured imaging/radiology or PACS workflows;
- billing, payments, claims, and insurance;
- pharmacy inventory, dispensing, or stock control;
- formal referral management;
- embedded video consultation/telemedicine;
- AI/LLM assistant, voice assistant, or clinical decision support;
- user-facing backup/recovery controls;
- integration registries or API-key management.

Documents may carry laboratory or radiology files, and appointments may carry external meeting information. Those facts do not create full laboratory, imaging, or telemedicine modules.

---

## 2. Verified repository snapshot

| Layer | Verified count/status |
|---|---:|
| Flutter named-route constants | **105** |
| Shared/pre-login routes | **10** |
| Patient routes | **21** |
| Doctor routes | **22** |
| Administrator routes | **27** (24 compatibility routes + Work/People/More hubs) |
| mCare Assistant routes | **25** (22 compatibility routes + Work/People/More hubs) |
| Laravel `/api/v1` route entries | **171** |
| API route groups | `admin` 61 · `auth` 17 · `doctor` 38 · `external` 6 · `fcm-tokens` 2 · `me` 5 · `patient` 42 |
| Laravel API controllers | **50** |
| Eloquent models | **34** |
| Database migrations | **20** |
| Laravel tests | **11 feature + 1 unit** |
| Flutter API clients | **25** |
| Flutter shared-state files | **14** |
| Flutter test files | **5** |

Counts are descriptive audit evidence, not architecture. The source files remain authoritative:

- Flutter routes: `frontend/lib/shared/constants/route_names.dart`
- Flutter route wiring: `frontend/lib/main.dart`
- Laravel routes: `backend/routes/api.php`
- Assistant permission keys: `backend/app/Models/AssistantPermission.php`

When one of these surfaces changes, update this snapshot in the same change.

The approved PDF was generated from the 99-route compatibility baseline. The six new Admin/Assistant hub entry routes are additive implementations of the PDF navigation and do not replace any legacy route. Regenerate the PDF atlas before treating it as an exact current route inventory; its visual, workflow, responsive, and security decisions remain the approved design reference.

### Runtime design rollout status

- Administrator and mCare Assistant dashboard/Work/People/More entry routes are wired to the shared Guided Operations hub.
- The existing Admin/Assistant feature and detail routes remain registered as compatibility destinations from that hub.
- Patient, Doctor, and External Clinical Access still use their existing route-level presentation while their PDF-approved shells are migrated.
- Legacy presentation code and decorative design assets have not been bulk-deleted; they remain only until the route-by-route parity and rollback gates in section 11 pass.

This status describes the repository at the verification date. Update it in the same change that cuts over another role or retires a legacy surface.

---

## 3. Quick start

### Prerequisites

- PHP 8.2+
- Composer
- MySQL 8+ or MariaDB 10.6+
- Flutter compatible with the SDK constraint in `frontend/pubspec.yaml`
- Chrome or another Flutter-supported target

The live application needs at least two terminals: Laravel and Flutter. A queue worker and Reverb server use separate terminals when those paths are being tested.

### 3.1 First-time backend setup — Terminal 1

PowerShell:

```powershell
Set-Location backend
composer install
Copy-Item .env.example .env
php artisan key:generate
# Configure DB_* in .env before migrating.
php artisan migrate --seed
php artisan storage:link
```

Command Prompt equivalent:

```bat
cd backend
composer install
copy .env.example .env
php artisan key:generate
php artisan migrate --seed
php artisan storage:link
```

### 3.2 Run the Laravel API — Terminal 1

```powershell
Set-Location backend
php artisan serve --host=127.0.0.1 --port=8000
```

API base: `http://127.0.0.1:8000/api/v1`

### 3.3 Run the queue worker — Terminal 2

The default local queue is database-backed. Run the worker when testing queued mail, broadcasts, and other jobs:

```powershell
Set-Location backend
php artisan queue:work --tries=3
```

### 3.4 Run Reverb — optional Terminal 3

Reverb is opt-in. It currently accelerates the vital-alert notification path; REST polling remains active as reconciliation and fallback.

```powershell
Set-Location backend
php artisan reverb:start --host=127.0.0.1 --port=8080
```

Fill `REVERB_*` in `backend/.env`, set `BROADCAST_CONNECTION=reverb`, and pass the matching app key to Flutter.

### 3.5 Run Flutter web against Laravel — Terminal 4

REST only:

```powershell
Set-Location frontend
flutter pub get
flutter run -d web-server --web-hostname localhost --web-port 8090 `
  --dart-define=MCARE_USE_BACKEND=true `
  --dart-define=MCARE_API_URL=http://127.0.0.1:8000/api/v1
```

REST plus opt-in Reverb:

```powershell
Set-Location frontend
flutter run -d web-server --web-hostname localhost --web-port 8090 `
  --dart-define=MCARE_USE_BACKEND=true `
  --dart-define=MCARE_API_URL=http://127.0.0.1:8000/api/v1 `
  --dart-define=MCARE_WS_URL=ws://127.0.0.1:8080 `
  --dart-define=MCARE_WS_APP_KEY=your-reverb-app-key
```

Open `http://localhost:8090`.

### 3.6 Demo mode without Laravel

```powershell
Set-Location frontend
flutter run -d web-server --web-hostname localhost --web-port 8090 `
  --dart-define=MCARE_USE_BACKEND=false
```

### 3.7 Useful verification commands

```powershell
# Backend
Set-Location backend
php artisan route:list --path=api/v1
php artisan test

# Frontend
Set-Location ..\frontend
flutter analyze
flutter test
```

If a process is already using port 8000, 8090, or 8080, stop that process or choose a different port and update the matching URLs.

---

## 4. Architecture

```text
Flutter application
  Web · Android · iOS · Windows
        |
        | HTTPS REST + Sanctum bearer authentication
        | optional WSS/Reverb vital-alert signal
        v
Laravel 12 API
  Controllers · middleware · services · policies/permission checks
        |
        +-- MySQL: application and clinical data
        +-- Queue: database locally; Redis recommended for production scale
        +-- Storage: private local/S3 delivery for medical files
        +-- Mail/FCM: credential-gated notification delivery
```

### Frontend boundaries

- Named routes are registered centrally in `main.dart`.
- `shared/` owns reusable UI, navigation, authentication, state, and role-neutral behavior.
- Role folders compose shared components and provide labels, routes, accent, and capability configuration.
- Existing API clients and shared state stores remain the canonical data and mutation layer.
- Responsive code changes composition only; it must not change authorization or business rules.
- `shared/` must never import Patient, Doctor, Admin, or Assistant feature folders.

### Current refresh and real-time behavior

- `SessionPoller` refreshes normal sessions every **30 seconds** and urgent SOS/alert sessions every **8 seconds**.
- Reverb is disabled unless both `MCARE_WS_URL` and `MCARE_WS_APP_KEY` are provided.
- The current WebSocket implementation handles the `vital.alert` event and triggers the same REST hydration path used by polling.
- Chat, SOS, all notifications, and all role channels are **not yet proven as complete WebSocket replacements**.
- Polling must not be reduced to a five-minute reconciliation interval until end-to-end subscription, authorization, reconnect, and missed-event tests pass for every critical event.

This keeps one state-mutation path regardless of whether REST polling or a WebSocket signal detected the change.

---

## 5. Approved design system

The PDF is the approved visual reference. Runtime implementation must converge on this one system; alternative glass, bubble, duplicated role themes, and one-off page styles are temporary migration code, not additional approved designs.

### 5.1 Visual tokens

| Token | Approved value/use |
|---|---|
| Patient accent | `#6366F1` |
| Doctor accent | `#057A55` |
| Administrator accent | `#7E3AF2` |
| Assistant accent | `#E3A008` |
| External session accent | `#3B82F6` |
| Primary text | `#0F172A` light · `#F8FAFC` dark |
| Secondary text | `#64748B` light · `#E2E8F0` dark |
| Critical | `#EF4444` |
| Warning | `#F59E0B` |
| Success | `#10B981` |
| Information | `#3B82F6` |
| Spacing scale | `4, 8, 12, 16, 24, 32, 48` |
| Standard radii | `8, 12, 18, 24`, plus pill |
| Page inset | 16 mobile · 24 tablet · 32 desktop |

Role accent identifies context. It never replaces semantic clinical state. A warning is amber for every role; a critical state is red for every role. Every state also includes an icon and readable label.

### 5.2 Visual rules

- Use clear white/dark surfaces, restrained borders, and very soft shadows.
- Frosted glass, decorative bubbles, and heavy gradients are not the default for clinical or operational pages.
- Reserve gradients for small brand or hero accents, never behind dense data or body text.
- Use one primary action per decision area.
- Keep labels visible after form entry; server validation is authoritative.
- Lists show minimum necessary PHI and open typed detail/action surfaces.
- Clinical actions follow: open detail → verify context → enter required information/reason → confirm → server result → durable receipt.
- Never expose a generic ambiguous **Resolve** action when the backend command is acknowledge, assign, close, revoke, reject, or resolve-with-reason.
- Every data surface implements loading, refreshing, ready, empty, no matches, stale/offline, error, permission revoked, session expired, conflict, and success-receipt states.

### 5.3 Accessibility

- Target WCAG 2.2 AA on web and equivalent mobile semantics.
- Minimum touch target: 48 × 48 px; practical desktop target: 44 × 40 px.
- Support keyboard navigation, visible focus, screen readers, reduced motion, orientation changes, and 200% text scale.
- Do not rely on color, animation, hover, or position alone.
- Charts require units, labeled axes, honest missing-data gaps, and a text alternative.

### 5.4 Shared component ownership

The final component library contains one authoritative implementation of:

- adaptive application shell and page header;
- buttons, fields, selectors, date controls, and confirmation dialogs;
- cards, status/filter chips, work-item/person rows, and adaptive tables;
- charts and accessible summaries;
- master/detail panes, bottom sheets, and drawers;
- notification bell, freshness/offline banner, toasts, and durable receipts;
- file upload, progress, validation, scan status, and failure state;
- loading skeleton, empty state, error state, and pagination.

Role folders may contain thin adapters only. They must not clone networking, state, permissions, validation, or component styling.

---

## 6. Navigation and responsive structure

### 6.1 Canonical top-level navigation

| Role | Destination 1 | Destination 2 | Destination 3 | Destination 4 | Global actions |
|---|---|---|---|---|---|
| Administrator | Home | Work | People | More | Search, bell, avatar |
| mCare Assistant | Home | Work | People | More | Authorized search, bell, avatar |
| Patient | Home | Health | Care | More | Bell, SOS, avatar |
| Doctor | Home | Work | Patients | More | Assigned-patient search, bell, SOS, avatar |
| External guest | No persistent navigation |  |  |  | Expiry and End session |

Persistent destinations represent user goals, not database tables. Existing named routes remain valid as deep links and compatibility entry points; a typed route-parent registry keeps the correct parent destination selected on child/detail routes.

### 6.2 Responsive tiers

| Tier | Width | Navigation | Layout |
|---|---:|---|---|
| Compact | `<600` | Four-item bottom navigation | Single column; full-page detail or bottom sheet |
| Medium | `600–1023` | Compact rail | One/two columns from available content width |
| Expanded | `1024–1439` | 220–240 px extended rail | Two-column hubs and master/detail |
| Wide | `>=1440` | Same extended rail | Max-width content with optional context pane |

Grid decisions use the width remaining **after** navigation, not full `MediaQuery` width. The same workflow and authorization apply at every breakpoint.

### 6.3 Page families

| Family | Purpose |
|---|---|
| Home | Truthful freshness, urgent summary, next safe actions, compact secondary counts |
| Work | Typed queue, plain-language filters, ranked priority, list/detail action flow |
| People/Patients | Authorized directory and contextual record/workspace |
| Health/Care | Patient-owned clinical tasks and care coordination |
| More | Infrequent tools, reports, configuration, profile, settings, and support |
| External workspace | Access gate, one-patient review, scoped contribution, receipt, session end |

Notifications remain a header bell. Patient and clinical-responder SOS stays visible and must not be buried in More.

---

## 7. Role experiences and capabilities

### 7.1 Administrator

**Home** answers: “What needs the platform team now?” It shows truthful freshness, urgent counts, and recommended next actions without claiming unsupported whole-platform health.

**Work** groups:

- SOS and vital alerts;
- healthcare-worker approvals;
- care requests and assignments;
- support tickets;
- operational messages.

**People** groups patients and staff/users. User details own account status, role changes, invitations, and assistant access grants.

**More** groups analytics, audit, security incidents, announcements, vital catalog, system settings, personal profile, and account settings.

Admin home must not expose fabricated trends, invented average-response times, or raw PHI when a privacy-minimized count is sufficient.

### 7.2 mCare Assistant

The Assistant uses the same shared staff shell and page families as Admin, with server-authorized content and actions filtered by live grants. The backend namespace remains `/admin`; there is no separate `/assistant` API namespace.

The 12 canonical grants are:

1. `can_approve_healthworkers`
2. `can_manage_care_requests`
3. `can_assign_patients`
4. `can_create_users`
5. `can_change_user_types`
6. `can_register_admin`
7. `can_register_assistant`
8. `can_view_activity_logs`
9. `can_view_security_incidents`
10. `can_access_emergency_location`
11. `can_manage_advertising`
12. `can_manage_vital_catalog`

Hidden navigation is not authorization. Laravel middleware/policies must reject an ungranted action. When a grant is revoked during a session, close restricted detail, clear restricted presentation data, and return to a safe destination with an explanation.

### 7.3 Patient

**Home** shows today’s care plan: next vital, medication dose, appointment, messages, and help/SOS.

**Health** groups vitals and trends, medications/doses, documents, and vital-report requests.

**Care** groups appointments, care team/requests, and secure messages.

**More** groups notifications entry, profile/health profile, privacy/external-access management, settings, and support.

Patient capabilities include onboarding, profile updates, vital recording/history, medication tracking, appointments, documents, messaging, notifications, SOS, support, care-team requests, and creation/revocation of external-access links.

### 7.4 Doctor

**Home** shows assigned caseload attention, today, and ranked clinical work.

**Work** groups SOS, alerts, visits/appointments, inbox/requests, reports due, and messages.

**Patients** is the assigned directory and patient workspace. The workspace groups existing content into:

- Overview;
- Monitoring: vitals, trends, alerts;
- Care plan: prescriptions, medications, meals, assigned vitals;
- Visits and notes: appointments, reports, timeline;
- Records and communication: documents and messages.

**More** groups schedule/reports, vital setup, profile, and settings.

All patient access remains caseload-scoped on the server. Search suggestions, counts, URLs, and cached state must not reveal unassigned patients.

---

## 8. External Clinical Access

A patient can create a time-limited link and spoken code for an outside clinician. The external clinician is a guest scoped to one patient record.

### Patient management points

- Care Team → External/Emergency access
- Settings → Privacy → External Clinical Access

Constraints: maximum five active links, expiry choices of 24 hours/3 days/7 days, no-lookalike access-code alphabet, resolve-code throttle, audit on create/revoke, and immediate patient revoke.

### Guest flow

```text
Open token link or enter code
→ confirm expiry and permitted scope
→ review one-patient summary
→ review vitals, medications, and document metadata
→ add only a scoped finding
→ receive a durable result/receipt
→ end, expire, or become revoked
```

Current API actions:

| Action | Endpoint |
|---|---|
| Resolve spoken code | `POST /api/v1/external/resolve-code` |
| Review shared summary | `GET /api/v1/external/{token}` |
| Add consultation note | `POST /api/v1/external/{token}/notes` |
| Record vital | `POST /api/v1/external/{token}/vitals` |
| Assign medication | `POST /api/v1/external/{token}/medications` |
| Upload document | `POST /api/v1/external/{token}/documents` |

There is no external login account, dashboard, global search, patient switcher, secure inbox, profile/settings area, notification identity, or telemedicine module. Those require a separate future backend project.

Production hardening should store only hashed bearer secrets where feasible, exchange codes for short portal sessions, enforce explicit operation scopes, keep files private/scanned, minimize PHI in the access gate, and audit successful access and writes.

---

## 9. Backend and API compatibility

Base URL: `/api/v1`.

| Group | Prefix | Authority |
|---|---|---|
| Authentication | `/auth/*` | Public/throttled and authenticated self-service operations |
| External access | `/external/*` | Public token/code guest, separately throttled |
| Shared account | `/me/*` | Authenticated user |
| Patient | `/patient/*` | Sanctum + patient role |
| Doctor | `/doctor/*` | Sanctum + doctor role + object/caseload checks |
| Admin/Assistant | `/admin/*` | Sanctum + admin/assistant role; assistant endpoints add permission checks |
| Push registration | `/fcm-tokens` | Authenticated user |

### Non-breaking contract rules

1. Keep all 105 named Flutter routes and their argument shapes during migration.
2. Do not rename or delete an API route to make the UI cleaner.
3. New hubs aggregate existing state; they do not create duplicate clients or stores.
4. Backend validation and authorization remain authoritative.
5. A feature flag changes presentation only; it is never permission evidence.
6. Preserve deep links and back-stack behavior with route-parent mapping.
7. Every state-changing action retains its existing service, audit, notification, and clinical side effects.
8. Route-count changes require README, tests, and PDF-atlas review.

### Current rate limits

- authentication surface: named `auth-login` limiter;
- external code resolution: 6/minute per IP;
- external token surface: 30/minute per token;
- authenticated API: 120/minute per user.

Verify limits with feature tests. A rate-limit label in documentation is not sufficient evidence that identifier selection and route placement are correct.

---

## 10. Security and production gates

### Security principles

- HTTPS only in production; `APP_DEBUG=false`.
- Sanctum bearer authentication and server-side role/object authorization.
- Force password change for staff-issued temporary passwords.
- Assistant grants checked on the backend, never inferred from hidden UI.
- Minimum-necessary PHI in lists, notifications, logs, WebSocket payloads, and analytics.
- Typed clinical/administrative commands with confirmation, reason where required, audit, idempotency, and durable receipt.
- Private medical-file delivery; no predictable public document URLs.
- Secrets stay in environment configuration and never enter source, logs, screenshots, analytics, or share URLs.
- SOS and alert recipients are scoped to explicit authority/care relationships.

### Production-blocking gates

| Gate | Exit evidence |
|---|---|
| Hosting and transport | Production HTTPS, correct CORS/Sanctum origins, `APP_DEBUG=false` |
| Database | Dedicated non-root user, automated encrypted backups, successful restore rehearsal |
| Email | OTP, reset, verification, and invite messages delivered using real SMTP |
| Account state | Suspended/disabled/unapproved users rejected on every protected surface |
| Session invalidation | Password, role, status, and grant changes invalidate affected sessions/tokens |
| OAuth | Mock/test OAuth impossible outside local/testing; production credentials configured |
| External access | Token/code/session expiry, revoke, throttling, operation scopes, and audit tests pass |
| Medical files | Private authorization, type/size validation, malware-scan policy, and safe download headers |
| SOS/alerts | Recipient, location, state-machine, acknowledge/resolve, and audit matrices pass |
| Authorization | Role, assistant-grant, object-type, object-target, and IDOR negative tests pass |
| Privacy/legal | Public privacy policy and terms explain health data, location/SOS, retention, deletion, and external sharing |
| Operations | Scheduler, queue worker, monitoring, backups, and incident response are supervised and tested |

No production cohort receives the redesigned workflow until its relevant gates are green.

---

## 11. Safe implementation and old-design retirement

The desired end state contains only the PDF-approved runtime design. Safe delivery is additive first and subtractive only after proven parity.

### Phase 0 — baseline and freeze

- Export the 105-route manifest and 171-route API inventory.
- Capture legacy screenshots at compact, medium, expanded, and wide sizes.
- Record route arguments, API payloads, mutations, audit events, notifications, and error behavior.
- Add route/deep-link/back-stack, role/grant, account-state, and IDOR tests.
- Resolve ownership of unrelated dirty-worktree changes before editing shared code.

**Exit:** legacy behavior is reproducible and regressions are detectable.

### Phase 1 — security/session prerequisites

- Close production mock-OAuth, account-state, session-revocation, recovery-token, SOS-recipient, and private-file findings.
- Add global client handling for 401, 403, permission changes, and expired sessions.
- Rehearse migrations and rollback on a production-like copy.

**Exit:** no open P0 finding for the cohort being enabled.

### Phase 2 — one shared Design System v2

- Implement the approved tokens and shared components under one namespace.
- Add responsive, dark-mode, semantics, keyboard, reduced-motion, and 200%-text tests.
- Do not globally restyle legacy widgets before route-level parity is available.

**Exit:** shared components pass tests independently and do not change flag-off screens.

### Phase 3 — route registry and rollout controls

- Map every existing route to role, parent destination, filter/detail context, required capability, and safe fallback.
- Preserve complete-profile and force-password gates outside the main shell.
- Use independent server-resolved rollout switches per role/cohort, default disabled until approved.
- Prove flag-off route and data behavior remains unchanged.

### Phase 4 — Administrator first

1. Guided Home: read-only, privacy-minimized, truthful freshness, ranked links.
2. Work read-only composer: alerts, SOS, approvals, care requests, assignments, support, messages.
3. Typed actions one workflow at a time: support → approvals → care requests/assignments → alert acknowledge → alert resolve-with-reason → SOS last.
4. People: patients/staff directory and contextual user actions.
5. More: analytics, audit, security, announcements, vital catalog, system/profile/settings.

Each command type receives success, validation, duplicate-submit, conflict, permission, audit, and rollback tests before the next type migrates.

### Phase 5 — mCare Assistant

- Reuse the same Admin components and adapters.
- Filter content/actions by live server grants.
- Test all 12 permission keys individually and in changing-session scenarios.
- Never fork an Assistant copy of Admin networking or workflow logic.

### Phase 6 — Patient

- Migrate Home, Health, Care, and More using existing routes and stores.
- Preserve onboarding, vitals, doses, appointments, messages, external-access management, and SOS behavior.
- Validate elderly-user touch targets, plain language, assistive technology, and intermittent connectivity.

### Phase 7 — Doctor

- Migrate Home, Work, Patients, and More.
- Compose the patient workspace from existing clinical sections without creating parallel chart state.
- Prove assigned-caseload scope on search, lists, deep links, notifications, and cached state.

### Phase 8 — External Clinical Access

- Apply the constrained guest shell and step-by-step contribution flow.
- Keep token expiry/scope visible and provide receipts/end states.
- Enable only after token/session, file, scope, revoke, audit, and PHI-minimization gates pass.

### Phase 9 — remove old designs

Old presentation code may be removed only route by route after all conditions below are true:

1. the new route has functional and visual parity;
2. compact, medium, expanded, dark, text-scale, keyboard, and screen-reader tests pass;
3. live-API success, validation, empty, offline/stale, 401/403, conflict, and server-error states pass;
4. UAT is approved by the affected role;
5. telemetry shows no release-blocking regression during the cohort window;
6. the rollback window has closed and a tagged previous release remains deployable;
7. no other route imports the legacy widget.

Then:

- delete the replaced page/layout and its obsolete styling only;
- remove unused glass/bubble/decorative design dependencies and assets;
- collapse temporary v1/v2 variants into one canonical component name;
- keep route names, API clients, state stores, policies, validation, and backend workflows;
- run repository-wide reference searches, analysis, tests, and release builds.

Do **not** bulk-delete old design folders before parity. That would make rollback impossible and can silently remove business behavior embedded in screens.

---

## 12. Testing, UAT, and rollback

### Required automated matrix

| Area | Minimum coverage |
|---|---|
| Routes/navigation | All named routes, arguments, guards, parent selection, deep links, back stack |
| Authentication | Login, lockout, verification, OTP, reset, invite, forced password, logout |
| Account security | Suspension, approval state, password/role/grant changes, session invalidation |
| Permissions | Every Assistant grant allows the intended operation and denies all others |
| Vitals/alerts | Normal and threshold breach, alert/notification/audit side effects, duplicate prevention |
| SOS | Trigger, authorized recipients/location, acknowledge/resolve, state transitions, audit |
| External access | Create → resolve → view/write → expire/revoke; IDOR and throttle negatives |
| Documents | Ownership, type/size, private delivery, failed upload, unauthorized download |
| Responsive UI | Compact, medium, expanded, wide, orientation, text scale, dark mode |
| Accessibility | Keyboard, focus, semantics, contrast, screen reader, reduced motion |
| Realtime | Private-channel auth, vital alert, reconnect, missed event, REST fallback |

### UAT cohorts

1. Internal Administrator
2. Selected Administrator operators
3. Selected mCare Assistants with varied grants
4. Patient pilot
5. Doctor pilot
6. External-access security/usability pilot

No role is enabled globally because a different role passed UAT.

### Rollback

- Use a tagged previous release and independent role/cohort rollout switches.
- Prefer forward-compatible, additive database migrations during the compatibility period.
- Disable the affected presentation immediately when a critical regression appears.
- Keep API contracts and old route entry points available through the rollback window.
- Never roll back by deleting or rewriting patient data.
- Record incident, affected cohort, data impact, mitigation, and follow-up test.

### Release gate

A role is complete only when product, clinical, security, accessibility, engineering, QA, and operations owners sign off with no open P0/P1 issue relevant to that release.

---

## 13. Environment and configuration

### Backend — `backend/.env`

| Variable | Purpose/production guidance |
|---|---|
| `APP_ENV`, `APP_DEBUG`, `APP_URL` | `production`, `false`, HTTPS API URL |
| `FRONTEND_URL` | HTTPS Flutter web URL used for external/OAuth/email links |
| `DB_*` | Dedicated least-privilege MySQL user |
| `SESSION_*`, `SANCTUM_STATEFUL_DOMAINS` | Session/Sanctum configuration for approved origins |
| `QUEUE_CONNECTION` | `database` locally; Redis recommended for production throughput |
| `BROADCAST_CONNECTION` | `log` locally or `reverb` when real-time is configured |
| `REVERB_*` | Reverb application credentials and server location |
| `MAIL_*` | Real SMTP/SES for production messages |
| `GOOGLE_CLIENT_*` | Production Google OAuth client and callback |
| `APPLE_CLIENT_ID` | Production Apple configuration if shipped |
| `FCM_*` | Firebase project/service-account values if push is shipped |
| `FILESYSTEM_DISK` | Private local storage or S3 |
| `AWS_*` | S3/SES credentials and region when AWS is used |

### Flutter dart-defines

| Define | Purpose |
|---|---|
| `MCARE_USE_BACKEND` | `true` for Laravel; `false` for demo/mock state |
| `MCARE_API_URL` | Laravel `/api/v1` base URL |
| `MCARE_WS_URL` | Optional Reverb WebSocket root |
| `MCARE_WS_APP_KEY` | Reverb application key paired with `MCARE_WS_URL` |
| `MCARE_GOOGLE_CLIENT_ID` | Google web OAuth client |
| `MCARE_APPLE_CLIENT_ID`, `MCARE_APPLE_REDIRECT_URI` | Apple web OAuth values |
| `MCARE_FIREBASE_*` | Firebase/push configuration |

Android release signing uses `frontend/android/key.properties`; start from `key.properties.example` and keep the real keystore/passwords out of version control.

---

## 14. Deployment

### Recommended production shape

| Concern | Suggested service | Requirement |
|---|---|---|
| Laravel API | AWS Lightsail/EC2 or equivalent | Web root is `backend/public`; HTTPS only |
| MySQL | RDS/Lightsail managed MySQL | Private network, backups, restore rehearsal |
| Queue/cache | Redis/ElastiCache at production scale | Supervised queue workers |
| Reverb | Supervised process behind Nginx/ALB | WSS upgrade headers and private-channel auth |
| Files | Private S3 bucket | Encryption, signed/authorized delivery, lifecycle policy |
| Email | Amazon SES or approved SMTP | Production sending access and monitored failures |
| Flutter web | S3 + CloudFront or web server | SPA fallback to `index.html`, including `/external?token=…` |
| DNS/TLS | Route 53 + ACM or equivalent | `api.` and `app.` HTTPS domains |
| Monitoring | Application/error/log monitoring | Alerts for 5xx, job failures, WebSocket failure, and backup failure |

### Laravel deployment sequence

```bash
cd /var/www/mcare/backend
composer install --no-dev --optimize-autoloader
php artisan migrate --force
php artisan storage:link
php artisan config:cache
php artisan route:cache
```

Run these under systemd/Supervisor or an equivalent process manager:

```bash
php artisan queue:work --tries=3
php artisan reverb:start --host=0.0.0.0 --port=8080
```

Scheduler:

```cron
* * * * * cd /var/www/mcare/backend && php artisan schedule:run >> /dev/null 2>&1
```

### Flutter web production build

```bash
cd frontend
flutter build web --release \
  --dart-define=MCARE_USE_BACKEND=true \
  --dart-define=MCARE_API_URL=https://api.yourdomain.com/api/v1 \
  --dart-define=MCARE_WS_URL=wss://api.yourdomain.com \
  --dart-define=MCARE_WS_APP_KEY=your-reverb-app-key
```

Before deployment, test login, patient vital → alert, SOS, messaging, file access, and patient external-link create → guest contribution → revoke on the actual HTTPS domains.

---

## 15. Google Play and Apple App Store

### Google Play

- Create and verify a Google Play Console developer account.
- Finalize the immutable Android `applicationId` before the first production upload.
- Generate and securely back up the upload keystore; configure `android/key.properties`.
- Host privacy policy, terms, support, and account-deletion information publicly.
- Complete health-app, data-safety, location/SOS, and external-record-sharing declarations accurately.
- Use internal testing before wider tracks.

Build:

```powershell
Set-Location frontend
flutter build appbundle --release `
  --dart-define=MCARE_USE_BACKEND=true `
  --dart-define=MCARE_API_URL=https://api.yourdomain.com/api/v1
```

Output: `frontend/build/app/outputs/bundle/release/app-release.aab`.

### Apple App Store

- Join the Apple Developer Program and use a Mac with supported Xcode.
- Register the Bundle ID and configure signing/capabilities.
- Complete App Store privacy labels for health data, documents, messages, location/SOS, and external sharing.
- Configure Apple Sign-In and push capabilities only when shipping them.
- Validate with TestFlight before App Store submission.

Build:

```bash
cd frontend
flutter build ipa --release \
  --dart-define=MCARE_USE_BACKEND=true \
  --dart-define=MCARE_API_URL=https://api.yourdomain.com/api/v1
```

Store review notes must explain that mCare coordinates monitoring and care, does not diagnose, does not replace clinicians, and does not replace emergency services.

---

## 16. Demo accounts

After `php artisan migrate --seed`, use password `demo-password`:

| Email | Role |
|---|---|
| `admin@mcare.health` | Administrator |
| `assistant@mcare.health` | mCare Assistant with all seeded grants |
| `dr.mensah@mcare.health` | Doctor |
| `dr.adeyemi@mcare.health` | Doctor — Endocrinology |
| `amara.okonkwo@example.com` | Patient with a rich demonstration chart |

Additional `@example.com` patients provide caseload variety.

Demo credentials are development data only. Never seed them into a production database.

---

## 17. Documentation policy

The maintained documentation set is intentionally small:

1. **This `README.md`** — current product, architecture, setup, contracts, security gates, implementation, testing, deployment, and operations.
2. **[Complete design blueprint PDF](output/pdf/mcare-complete-application-design-blueprint.pdf)** — approved screen-by-screen visuals, responsive examples, route atlas, workflows, traceability, and stakeholder review record.

Do not create competing role-specific design plans or duplicate README files. When implementation changes product truth, update this README in the same change. When an approved visual/navigation decision changes, regenerate and reapprove the single PDF.

The PDF contains visual detail that cannot be represented faithfully in plain Markdown—high-fidelity mockups, responsive compositions, complete screen atlas, and visual approval record—so it remains the authoritative visual companion rather than being copied into this README.

---

## 18. License

Private — all rights reserved. Not licensed for public distribution.
