# mCare — Remote Patient Monitoring Platform

**mCare** is a full-stack Remote Patient Monitoring (RPM) and healthcare-management platform. Patients record vitals at home; the Laravel backend evaluates readings against clinical thresholds; care teams respond through alerts, messaging, appointments, prescriptions, reports, documents, and emergency SOS workflows.

**Stack:** Laravel 12 REST API (`backend/`) · Flutter 3 (`frontend/`, web + Android + iOS + Windows) · MySQL 8+

**Repository truth last verified:** 2026-08-29

**Release status:** automated code, migration, analysis, test, and web-build
gates are green. Production approval remains conditional on the external,
infrastructure, security, privacy, load, accessibility, and UAT checks listed
below.

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
- FCM token registration and opt-in Laravel Reverb invalidation channels for
  patient, clinician, administrative, messaging, notification, SOS, care,
  report, support, document, appointment, medication, settings, and audit data.

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
| Flutter named-route constants | **110** |
| Shared/pre-login routes | **10** |
| Patient routes | **25** |
| Doctor routes | **23** |
| Administrator routes | **27** (24 compatibility routes + Work/People/More hubs) |
| mCare Assistant routes | **25** (22 compatibility routes + Work/People/More hubs) |
| Laravel `/api/v1` route entries | **204** |
| API route groups | `admin` 77 · `auth` 23 · `doctor` 45 · `external` 7 · `fcm-tokens` 2 · `me` 5 · `patient` 45 |
| Laravel API controllers | **60** |
| Eloquent models | **36** |
| Database migrations | **26**, all applied in the verified local MySQL environment |
| Application tables | **45**, including Laravel cache/queue/session infrastructure |
| Laravel automated tests | **142 passing, 671 assertions** across 28 feature files + 1 unit file |
| Flutter API clients | **27** |
| Flutter shared-state files | **14** |
| Flutter test files | **32**; **158 passing**, 9 intentionally skipped platform cases, 0 failing |

Counts are descriptive audit evidence, not architecture. The source files remain authoritative:

- Flutter routes: `frontend/lib/shared/constants/route_names.dart`
- Flutter route wiring: `frontend/lib/main.dart`
- Laravel routes: `backend/routes/api.php`
- Assistant permission keys: `backend/app/Models/AssistantPermission.php`

When one of these surfaces changes, update this snapshot in the same change.

### Repository structure

```text
mcares3/
  backend/                     Laravel 12 API
    app/Events/                queued broadcast events
    app/Observers/             model lifecycle triggers
    app/Services/              clinical, notification, push, report, realtime logic
    app/Http/Controllers/      versioned REST controllers
    app/Models/                Eloquent persistence and API mapping
    routes/api.php             /api/v1 contract
    routes/channels.php        private Reverb authorization
    routes/console.php         scheduled escalation
    database/migrations/       forward-only schema history
    database/seeders/          synthetic role-complete test dataset
    tests/                     PHPUnit feature/unit coverage
  frontend/                    Flutter multi-platform application
    lib/core/api/              REST transport and DTO mappers
    lib/core/auth/             OAuth platform adapters
    lib/core/env/              compile-time environment switches
    lib/core/realtime/         Reverb channel, poller, domain listeners
    lib/shared/                role-neutral state, navigation, services, UI
    lib/admin|doctors|patients|mcare_assistant/
                                role compositions and workflows
    test/                      Flutter unit/widget/navigation coverage
  scripts/                     developer start/reset helpers
  deploy/                      Nginx, systemd, k6, monitoring/recovery runbook
  output/pdf/                  approved visual blueprint
  README.md                    canonical engineering/product status
```

The approved PDF was generated from the 99-route compatibility baseline. The six new Admin/Assistant hub entry routes are additive implementations of the PDF navigation and do not replace any legacy route. Regenerate the PDF atlas before treating it as an exact current route inventory; its visual, workflow, responsive, and security decisions remain the approved design reference.

### Runtime and upgrade status

- Administrator and mCare Assistant dashboard/Work/People/More entry routes are wired to the shared Guided Operations hub.
- The existing Admin/Assistant feature and detail routes remain registered as compatibility destinations from that hub.
- Patient, Doctor, and External Clinical Access still use their existing route-level presentation while their PDF-approved shells are migrated.
- Legacy presentation code and decorative design assets have not been bulk-deleted; they remain only until the route-by-route parity and rollback gates in section 11 pass.
- Backend syntax, all migrations, route middleware, Composer metadata, Flutter analysis, both automated suites, and a release web build were verified on 2026-08-28. The 2026-08-29 authentication upgrade re-verified the complete backend and Flutter suites after adding secure-session, recovery, and Apple nonce coverage.
- Flutter analysis has no error or warning diagnostics. It currently reports 332 informational/deprecation lints that do not fail the build and should be retired incrementally.
- A live browser smoke test remains unverified because this review environment had no connected browser. Automated boot-render, responsive clinical layout, navigation, and deep-link widget tests passed.

This status describes the repository at the verification date. Update it in the same change that cuts over another role or retires a legacy surface.

---

## 3. Quick start

### Prerequisites

- PHP 8.2+
- Composer
- MySQL 8+ or MariaDB 10.6+
- Flutter compatible with the SDK constraint in `frontend/pubspec.yaml`
- Chrome or another Flutter-supported target

For an existing configured checkout, the recommended non-destructive launcher
starts Laravel, Reverb, the queue worker, and the scheduler as tracked hidden
processes, then opens Flutter in Chrome with matching REST and WebSocket
defines:

```powershell
.\scripts\start-local.ps1

# Stop the tracked PHP services when finished.
.\scripts\stop-local.ps1
```

Runtime output is written to `backend/storage/logs/local-runtime/`. Use
`-SkipFrontend` for backend services only, `-NoRealtime` to test polling-only
fallback, or `-FlutterDevice web-server` for a headless web target. With the
headless target, open `http://localhost:8090` before using hot restart;
otherwise Flutter correctly reports `No client connected` and the restart
times out. `fresh-start.ps1` is the destructive reset/reseed equivalent and
prompts before dropping tables.

The following manual commands remain available when individual service logs
need to stay in separate terminals.

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

For local recovery testing, keep `SMS_DRIVER=log`; the six-digit SMS body is
written to `backend/storage/logs/laravel.log`. Configure
`SMS_DEFAULT_COUNTRY_CODE` (digits only) whenever stored/test phone numbers use
a local trunk prefix. A production deployment must use `SMS_DRIVER=twilio`,
real Twilio credentials, and a transactional `MAIL_MAILER`; the readiness audit
fails those gates when they are absent.

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

The default local queue is database-backed. Run the worker when testing queued mail, Reverb broadcasts, and other jobs. A process supervisor is required in production:

```powershell
Set-Location backend
php artisan queue:work --tries=3
```

### 3.4 Run Reverb — optional Terminal 3

Reverb is opt-in. When configured it carries small, PHI-free invalidation
signals across all live application domains. Authorised clients then re-read
canonical data from REST. REST polling remains active as reconciliation and
automatically becomes the primary path if channel authorization or the socket
connection fails.

```powershell
Set-Location backend
php artisan reverb:start --host=127.0.0.1 --port=8080
```

Fill `REVERB_*` in `backend/.env`, set `BROADCAST_CONNECTION=reverb`, run the
queue worker, and pass the matching app key to Flutter. The API and WebSocket
application key must refer to the same Reverb application.

### 3.5 Run Flutter web against Laravel — Terminal 4

REST only:

```powershell
Set-Location frontend
flutter.bat pub get
flutter.bat run -d chrome --web-hostname localhost --web-port 8090 `
  --dart-define=MCARE_USE_BACKEND=true `
  --dart-define=MCARE_API_URL=http://127.0.0.1:8000/api/v1
```

REST plus opt-in Reverb:

```powershell
Set-Location frontend
flutter.bat run -d chrome --web-hostname localhost --web-port 8090 `
  --dart-define=MCARE_USE_BACKEND=true `
  --dart-define=MCARE_API_URL=http://127.0.0.1:8000/api/v1 `
  --dart-define=MCARE_WS_URL=ws://127.0.0.1:8080 `
  --dart-define=MCARE_WS_APP_KEY=your-reverb-app-key
```

Chrome opens the application URL automatically. If `-d web-server` is used
instead, manually open `http://localhost:8090` before hot restart.

### 3.6 Explicit UI fixture mode without Laravel

Normal local development uses seeded Laravel/MySQL data. The legacy in-memory
fixtures are retained only for isolated UI work and require both flags, so an
API outage can never silently replace real data with a fictional patient:

```powershell
Set-Location frontend
flutter.bat run -d chrome --web-hostname localhost --web-port 8090 `
  --dart-define=MCARE_USE_BACKEND=false `
  --dart-define=MCARE_ALLOW_DEMO_DATA=true
```

### 3.7 One-command database dataset and real-time simulations

For a clean local database, run the guarded reset helper. It prints the exact
database and asks for confirmation unless `-Force` is supplied:

```powershell
.\scripts\fresh-start.ps1 -ResetOnly -SkipDeps
```

The equivalent backend commands are:

```powershell
Set-Location backend
php artisan migrate:fresh --seed
php artisan mcare:demo-status --strict --json
```

`DatabaseSeeder` calls seven ordered seeders and creates one coherent snapshot
for every supported role. Snapshot installation suppresses row-by-row Reverb
invalidation jobs; it does not disable runtime observers. To prove real model
triggers and client refresh behavior, run Reverb and a queue worker, sign in on
one or more clients, then execute:

```powershell
php artisan mcare:simulate vital-critical
php artisan mcare:simulate sos --patient=MCR-001284
php artisan mcare:simulate message
php artisan mcare:simulate appointment
php artisan mcare:simulate all --json
```

These commands write genuine `vital_readings`, `sos_events`, `chat_messages`,
`appointments`, and actionable notifications through the same models/notifier
services used by the API. Observers emit normal PHI-free private-channel
invalidations, while REST reconciliation remains the recovery path. Simulation
is blocked in production unless an operator deliberately supplies `--force`.

The dataset deliberately leaves cache, sessions, queue/failed jobs, password
and email codes, Sanctum tokens, FCM device tokens, and compatibility-only
staff notification state empty. Those values must be generated by runtime
behavior or a real provider/device and are unsafe or misleading as fixtures.

### 3.8 Useful verification commands

```powershell
# Backend
Set-Location backend
php artisan route:list --path=api/v1
php artisan test
php artisan mcare:demo-status --strict
php artisan mcare:readiness --strict

# Frontend
Set-Location ..\frontend
flutter.bat analyze
flutter.bat test
flutter.bat build web --release
```

If a process is already using port 8000, 8090, or 8080, stop that process or choose a different port and update the matching URLs.

---

## 4. Architecture

```text
Flutter application
  Web · Android · iOS · Windows
        |
        | HTTPS REST + Sanctum bearer authentication
        | optional WSS/Reverb private invalidation signals
        v
Laravel 12 API
  Controllers · middleware · services · role/object authorization
        |
        +-- Eloquent observers -> RealtimeSignalService
        |      -> queued, after-commit, PHI-free `session.changed`
        |
        +-- MySQL: essential durable application and clinical data
        +-- Queue/cache/session: database locally; Redis recommended at scale
        +-- Storage: private local/S3 delivery for medical files
        +-- Mail/FCM: credential-gated notification delivery

Private channels
  private-user.{userId}  per-user and assigned-care updates
  private-app            global catalog/announcement updates
  private-staff          admin and mCare Assistant operations
  private-external.{id}  one valid guest token; no user/staff channel access
```

The database and REST API remain the source of truth. Reverb never carries a
patient chart or a complete notification. It only says which domain changed,
after the surrounding transaction commits. This avoids duplicate mapping
logic, protects PHI, and makes a missed socket event recoverable by the next
REST reconciliation.

### Frontend boundaries

- Named routes are registered centrally in `main.dart`.
- `shared/` owns reusable UI, navigation, authentication, state, and role-neutral behavior.
- Role folders compose shared components and provide labels, routes, accent, and capability configuration.
- Existing API clients and shared state stores remain the canonical data and mutation layer.
- Responsive code changes composition only; it must not change authorization or business rules.
- `shared/` must never import Patient, Doctor, Admin, or Assistant feature folders.

### Authentication, recovery, and device-session architecture

Authentication is API-backed in normal builds. Password, Google, Apple,
verification, invitation, and recovery continuations all converge on one
Sanctum payload containing the user, role/profile gates, an absolute token
expiry, and the selected persistence mode.

- **Keep me signed in:** unchecked sessions expire after
  `MCARE_SESSION_TOKEN_MINUTES` (8 hours by default) and live only in browser
  `sessionStorage` or native process memory. Checked sessions expire after
  `MCARE_REMEMBER_TOKEN_MINUTES` (30 days by default) and use
  `flutter_secure_storage`. The web tab marker survives refresh but not tab
  closure, so refresh does not incorrectly end a temporary session. The server
  enforces both expiries and caps active device sessions at
  `MCARE_MAX_DEVICE_SESSIONS` (10 by default).
- **Session recovery:** app startup validates the saved bearer token with
  `/auth/me`. A 401/403 clears it. A temporary network/server outage retains a
  still-unexpired remembered identity and token for automatic reconnection
  instead of silently converting the outage into a logout.
- **Device control:** every token has a platform/device label and appears in
  Settings → Signed-in devices. Users can revoke another device individually;
  password resets, administrative resets, role/status invalidation, suspension,
  and rejection revoke affected sessions and stale push registrations.
- **Email reset:** `/auth/forgot-password` creates a random, hashed,
  single-use token and sends a deep link through Laravel Mail. The default
  expiry is 60 minutes. Successful use deletes the grant, resets lockout state,
  and signs out every device.
- **Phone reset:** the user explicitly selects SMS and supplies the account
  phone. Numbers are canonicalized into indexed `users.phone_e164` values;
  recovery proceeds only when one account owns the number. A six-digit code is
  stored only as a password hash, expires after 10 minutes, burns after five
  failed attempts, and is exchanged once for the normal reset grant. Known and
  unknown identifiers receive indistinguishable responses.
- **Recovery presentation:** sign-in opens one responsive Account Recovery
  sheet. Email/SMS selection, OTP verification, password entry, and completion
  transition inside that sheet with a three-step indicator. The historical
  `/forgot-password` and `/reset-password` routes remain compatibility/deep-link
  launchers over sign-in; an emailed token enters the same sheet at the final
  step and the URL is normalized back to `/login` when it closes. Request,
  verification, reset arguments, and UI now live in
  `frontend/lib/auth/forgot_password_view.dart`; the redundant standalone reset
  view was removed.
- **Email verification:** registration creates an unverified account and sends
  a hashed, single-use, 15-minute code. Until it succeeds, protected role data,
  broadcast authorization, settings, and push registration are blocked.
- **Social identity:** Google and Apple use platform SDK identity tokens which
  are verified server-side for signature/provider, audience, expiry, subject,
  and verified email where applicable. Apple additionally requires a cached,
  single-use server challenge/nonce, preventing replay of a captured identity
  token. Mock social identities remain disabled by default and can never sign
  in staff roles.
- **Background notifications:** after a verified login or restored session, the
  server preference is applied before requesting OS permission or registering
  FCM. Android/iOS/web delivery continues while the UI is backgrounded because
  the provider holds the device registration; opening a notification refreshes
  canonical REST state and routes to the role-correct screen. Disabling push or
  signing out unregisters that device.

### Application-level triggers and event flow

`RealtimeModelObserver` is registered centrally for 31 durable models. Create,
update, delete, and restore operations are mapped by `RealtimeSignalService`
to an audience and one or more data domains. This is an application-level
trigger rather than a MySQL network trigger, so it works consistently in
MySQL/MariaDB and SQLite tests and remains aware of authenticated user/care
relationships.

The observed domains are:

- identity/profile, permissions, settings, and system configuration;
- vitals, thresholds, tracked/assigned vitals, alerts, and notifications;
- medications/doses, appointments, documents, reports, and meal plans;
- conversations/messages and support tickets/replies;
- SOS, care requests/providers/assignments, announcements, and audit events;
- external-access token lifecycle.

Flow:

1. A controller or service commits a durable model change.
2. The observer resolves affected users/care team/staff without writing a
   temporary event row.
3. `RealtimeDataChanged` is queued after commit on private channels.
4. Flutter debounces events for 250 ms and refreshes through the existing REST
   session mapper. Screens outside a role-session payload subscribe only to
   their relevant domains.
5. If authorization, Reverb, or the socket fails, normal polling resumes
   immediately.

Bulk query updates do not fire Eloquent observers. Messaging read receipts and
notification “mark all read” paths therefore emit an explicit signal after a
successful update. This rule must be followed for future mass-update code.

### Current refresh and real-time behavior

- `SessionPoller` refreshes normal sessions every **30 seconds** and urgent SOS/alert sessions every **8 seconds**.
- Reverb is disabled unless both `MCARE_WS_URL` and `MCARE_WS_APP_KEY` are provided.
- A socket is considered live only after every required private-channel subscription succeeds. Connected sessions use a **5-minute** reconciliation sweep; disconnects restore 30/8-second polling.
- `session.changed` covers all observed domains. The previous `vital.alert` event remains accepted for rolling-deployment compatibility.
- Patient and staff session fingerprints include meaningful row content, not only list lengths, so status changes, read receipts, and same-size list updates rebuild the UI.
- Independently loaded analytics, announcements, care-request, security, report-signature, external-access, consent, and dossier screens use domain-filtered refresh listeners.
- External guest sessions authorize only their token-owned private channel,
  refresh canonical REST data on invalidation, and retain a 30-second
  reconciliation timer for missed events and temporary disconnects.
- Live network delivery still requires an actual Reverb process, queue worker, matching credentials, reverse-proxy WebSocket support, and production WSS verification.

This keeps one state-mutation path regardless of whether REST polling or a WebSocket signal detected the change.

### Database usage and lightweight-data policy

Persist only information that must survive process restarts, audit/recovery, or
cross-device use: users and authorization, clinical readings and records,
care/workflow state, messages, actionable notifications, audit trails, tokens,
documents, and integration delivery registrations.

The 45 tables are grouped as follows:

- identity/security: users, profiles, contacts, settings, permissions, invites,
  password/email tokens, Sanctum tokens, external-access tokens, and sessions;
- clinical: vital catalog/readings/ranges/tracking/assignments, medications and
  doses, appointments, documents, reports/report requests, and meal plans;
- care/workflow: providers, care requests/assignments, SOS, announcements,
  system settings, and audit entries;
- communication/operations: conversations/messages, actionable notifications,
  support tickets/replies, FCM registrations, jobs/failed jobs/batches, and
  cache/locks.

Do not persist presentation-only state:

- dashboard totals, indicators, list counts, active badges, and search/filter results are calculated from canonical rows;
- conversation unread counts are derived from unread `chat_messages` for the
  current viewer, and latest-message ordering is computed from message time;
- staff alert/SOS/request indicators are computed from live role-session data;
- client-computed staff notification read/resolved state is session-local and
  the compatibility endpoints intentionally perform no database reads/writes;
- real-time invalidations are queue/broker messages, not application-table rows.

Seed installation follows the same rule. `WorkflowDemoSeeder` fills durable
clinical and operational workflows, while `RealtimeSignalService::withoutSignals`
prevents a fresh snapshot from enqueueing hundreds of useless intermediate
invalidations. Runtime writes and `mcare:simulate` immediately leave that guard
and use the normal observer, notifier, queue, Reverb, and REST-reconciliation
paths. `mcare:demo-status --strict` verifies role and relationship coverage.

The legacy `conversations.unread_count`, `conversations.last_message_at`, and
`staff_notification_states` schema are retained temporarily for a safe rolling
upgrade, but current code no longer writes derived state to them. Remove those
columns/table only after every deployed older client is outside the rollback
window and a backup/restore rehearsal has passed.

Existing composite indexes cover the high-frequency vital history, unread
notification, active external-link, and active SOS queries. The doctor session
now uses grouped alert counts, eager loading, and a latest-reading subquery to
avoid per-patient queries and loading full reading history. Conversation lists
eager-load the latest message and calculate unread counts in SQL.

### Progress report — verified 2026-08-29

#### Completed in this remediation

- Corrected the reviewed local `APP_URL`/`FRONTEND_URL` so generated links stay
  on localhost and explicitly disabled mock social authentication.
- Added non-destructive, idempotent local start/stop orchestration for the API,
  Reverb, queue worker, and scheduler, with tracked PIDs and separate logs.
- Made Chrome the default Flutter web target and supplied matching REST/Reverb
  Dart defines; headless `web-server` use now explains the required browser
  connection before hot restart.
- Started and live-probed the complete local runtime, drained the 439-event
  invalidation backlog to zero, and confirmed zero failed queue jobs.
- Reconciled the architecture, route, migration, model, controller, table,
  integration, and test inventories in this README against the live tree.
- Implemented native Google identity-token acquisition and Apple authorization
  adapters, with fail-closed production behavior and backend audience checks.
- Added iOS Apple/remote-notification entitlements, an iOS Google callback
  configuration seam, Android critical-notification channel creation, and
  fail-closed Android release signing.
- Added token-scoped guest Reverb authorization and external-session live
  invalidation with REST reconciliation; a guest can never authorize a user,
  staff, app, or another guest's channel.
- Added FCM HTTP-v1 service-account validation, relative-path resolution,
  permanent-token cleanup, and deployment-specific web service-worker config.
- Added `/ready`, `php artisan mcare:readiness --strict`, Nginx WSS and systemd
  templates, a k6 smoke profile, and backup/recovery/monitoring/rollback runbooks
  under `deploy/`.
- Reworked alert presentation into one shared escalation engine plus a compact
  non-blocking banner, actionable urgent queue, and responsive notification
  preview sheet. The bell now separates urgent clinical work from routine
  updates, avoids duplicate rows, shows severity/age/ownership, and preserves
  direct routes to the complete role inbox.
- Unified foreground and tapped push behavior across patient, doctor, admin,
  and assistant roles: each push refreshes the canonical session first,
  de-duplicates staff alerts against Reverb banners, and offers the correct
  role destination instead of silently refreshing.
- Replaced automatic frontend fixture activation with explicit opt-in, removed
  preset login identity/password values, and kept normal builds API-backed.
- Added one ordered, production-guarded database snapshot covering every active
  patient and role: settings, contacts, care assignment, readings, thresholds,
  medication/doses, past/future appointments, documents, messages, alerts,
  support, meal plans, reports/consent stages, external access, invitations,
  audit, SOS events, and responder actions.
- Added `mcare:demo-status --strict` with 22 relationship/role gates and
  `mcare:simulate` scenarios that generate actual vital, SOS, message, and
  appointment mutations through the existing notifier and real-time pipeline.
- Prevented seed-time broadcast storms, added live invalidation for SOS response
  actions and invitations, and stopped seed/simulation code from writing legacy
  derived conversation counters/timestamps.
- Implemented real remember-me semantics with server-enforced short/long
  expiries, secure persistent storage, tab-scoped temporary storage, device
  labels, a ten-session cap, Settings-based session review/revocation, and
  outage-safe restoration that does not erase a valid remembered credential.
- Replaced the placeholder recovery screen with complete email-link and
  phone-SMS branches. Reset tokens and OTPs are hashed, expiring and single-use;
  OTPs burn after five failures, reset success revokes sessions and FCM tokens,
  and responses do not disclose whether an account/phone exists.
- Added canonical indexed E.164 phone matching, Twilio delivery plus a local
  log driver, SMS configuration readiness checks, and a production-safe rule
  that refuses ambiguous/shared phone numbers for password recovery.
- Added single-use server nonce binding to Apple Sign-In and preserved the
  user's remember choice across email verification. Invalid password sign-in
  now returns the correct generic `401 Unauthorized` response.
- Deferred notification permission until a verified authenticated user exists,
  applies the server push preference before registration, restores FCM
  registration on a remembered session, and removes stale delivery tokens when
  credentials or account authority change.

#### Fully functional in code and connected to real-time invalidation

- Authenticated patient, doctor, administrator, and mCare Assistant REST
  session hydration, role gates, object/caseload checks, and fallback polling.
- Inactive-account middleware protects role data and broadcast authorization;
  suspension/status and staff-role changes revoke existing Sanctum and FCM
  tokens while pending users retain access only to verification and
  approval/session self-service routes.
- Vitals/threshold evaluation, alert creation/resolution, notifications, SOS,
  care requests/assignments, appointments, medications/doses, reports,
  documents, meal plans, profiles, settings, announcements, support, audit,
  external-link management, and messaging model changes.
- SOS responder actions and staff invitation lifecycle changes now produce the
  same scoped invalidation signals as the surrounding workflow.
- Sanctum-protected `/broadcasting/auth`, CORS coverage, private per-user/app/
  staff channel authorization, token-protected guest-channel authorization,
  reconnect backoff, ping/pong, event debounce, disconnect fallback, and
  periodic reconciliation when connected.
- Derived unread counts and last-message ordering; messages are created unread
  for the other participant. Doctors cannot open another clinician’s thread,
  and administrative oversight cannot inject messages into threads the admin
  has not joined.
- Dynamic dashboard counters, indicators, alert queues, and staff notification
  presentation state with no new application-table storage.

#### Functional but dependent on deployment configuration

- Reverb real-time delivery: code, the local WebSocket handshake, private-user
  and guest authorization, queue delivery, scheduler startup, WSS proxy
  template, and systemd units are implemented. Installation and an external
  production-domain WSS probe remain deployment evidence.
- FCM push, SMTP email, Twilio SMS recovery, Google web/native OAuth, Apple
  web/native authorization, private S3 storage, and geolocation have application code and configuration
  seams. They still require the owner's vendor credentials, platform-console
  registration, signing, and real-device/domain verification.
- The database-backed queue/cache/session setup is suitable for local/small
  deployments; Redis is recommended for horizontally scaled production.

The code paths above use real seeded MySQL records locally. What remains
unproven with real external data is provider delivery: Firebase/APNs device
delivery, SMTP inbox/bounce delivery, Twilio carrier delivery, Google/Apple
production identities, S3 object policy/scanning, geolocation permissions, and
public-domain HTTPS/WSS.
No fake device token, OAuth identity, email receipt, or cloud credential is
inserted to make these gates appear complete.

#### Functional but still requires improvement

- The design-system migration remains route-by-route; compatibility screens
  are intentionally retained until visual/UAT parity is signed off.
- Flutter has 332 non-failing informational lints, mainly SDK deprecations and
  style suggestions. Retire them incrementally to avoid a risky bulk rewrite.
- Lists are deliberately capped, but high-volume installations should replace
  remaining fixed limits with cursor pagination and add query/load telemetry.
- The doctor vital-report-request index endpoint has no current Flutter caller.
  It is retained as a non-breaking compatibility endpoint until usage telemetry
  and the rollback window permit removal.

#### Not connected to real-time data

- Static UI/design catalogs, privacy/terms content, deployment configuration,
  store metadata, and human approval records do not require live subscriptions.
- Email, push delivery, backups, and monitoring are event-driven external
  operations rather than screen data sources; their outcomes must be monitored
  by the selected providers.
- Password/email challenges, login sessions, device tokens, cache, queue rows,
  and derived counters are intentionally runtime-created rather than seeded.

#### Missing product modules

Structured laboratory, imaging/PACS, billing/payments/claims/insurance,
pharmacy stock/dispensing, formal referrals, embedded video visits, AI/voice
clinical assistance, user-facing backup/recovery, and an integration registry
remain outside the implemented product scope described in section 1.

#### Still requires testing or verification

- Live production HTTPS/WSS end-to-end testing after the supplied Nginx/systemd
  templates are installed, including reconnect, missed-event reconciliation,
  and concurrent clients.
- Real SMTP/SMS/OAuth/FCM/S3 credentials; mobile notification permissions;
  Android app-bundle and iOS/TestFlight builds on signing-capable hosts.
- Manual browser smoke/UAT, screen reader/keyboard/200%-text checks, clinical
  workflow acceptance, load tests, backup restore, monitoring, incident runbook,
  and privacy/legal approval.

Automated verification completed in this review: PHP syntax for the application
surface, all 26 migrations applied locally, 204 API routes, 142 Laravel tests,
full Flutter/Dart analysis with no errors or warnings, 32 Flutter test files with
158 passing tests, 9 intentionally skipped platform cases and zero failures,
Composer validation, and a successful release web build from the preceding
production-gate pass. The final backend suite passed 142 tests with 671
assertions, including account verification, short/remembered expiry, device
revocation, email/SMS recovery, Apple nonce replay rejection, and FCM
invalidation. The secure-session tests cover remembered persistence, short
session expiry, and clearing behavior. Startup rendering and active support
ticket access were also regression-tested after the authentication upgrade.

Local runtime verification on 2026-08-28 additionally confirmed HTTP health on
port 8000, a Reverb `101 Switching Protocols` handshake on port 8080, receipt of
`pusher:connection_established`, authenticated private-user channel signing,
and active queue/scheduler processes. The pre-existing queue contained only
PHI-free `RealtimeDataChanged` invalidations and drained without failed jobs.
FCM service credentials and Apple credentials are not configured in the
reviewed local environment; those integrations correctly remain deployment
gates rather than using fabricated credentials.

Authentication verification on 2026-08-29 confirmed all 26 migrations on the
local MySQL database, canonical phone values for all 11 users with phone data,
zero non-expiring Sanctum tokens, and the complete 142-test Laravel suite. Real
SMTP, Twilio, Google, Apple, FCM/APNs and mobile-background delivery still need
the owner credentials and device/domain evidence listed below.

The final local `mcare:readiness --json` snapshot reports **10 pass, 5 warn,
4 fail**. The failures are intentionally fail-closed deployment inputs:
`APP_DEBUG=true` in the local environment, missing Twilio/default-country-code
configuration, missing FCM project/service-account credentials, and a missing
Apple client ID. Warnings cover the non-production environment/HTTP URLs,
database queue/session drivers, and local object storage. These are not hidden
or replaced with test credentials; section 10 lists the evidence needed to
promote each gate.

Dataset verification on 2026-08-28 rebuilt the local `mcare` MySQL database
from the then-current migrations, passed all 22 demo-coverage gates, and confirmed zero
seed-generated queue/failed jobs. A live `mcare:simulate all` run created a
critical vital, SOS, message, appointment, and their notifications; a temporary
Reverb server received all 14 queued broadcasts, the worker completed every
job, and both queue tables returned to zero failures/backlog.

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
| Authorize own live channel | `POST /api/v1/external/{token}/broadcasting/auth` |
| Add consultation note | `POST /api/v1/external/{token}/notes` |
| Record vital | `POST /api/v1/external/{token}/vitals` |
| Assign medication | `POST /api/v1/external/{token}/medications` |
| Upload document | `POST /api/v1/external/{token}/documents` |

There is no external login account, dashboard, global search, patient switcher, secure inbox, profile/settings area, notification identity, or telemedicine module. Those require a separate future backend project.

The guest portal subscribes to `private-external.{accessId}` when Reverb is
configured. The token-specific authorization endpoint permits exactly that
channel. Events contain invalidation metadata only, and the portal re-reads the
token-authorized REST record. A 30-second REST sweep covers missed events;
revocation produces a final invalidation and the subsequent read fails closed.

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

1. Keep all 110 named Flutter routes and their argument shapes during migration.
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
| SMS recovery | Twilio credentials/from number, correct default country code, and real-carrier OTP delivery |
| Account state | Suspended/disabled/unapproved users rejected on every protected surface |
| Session invalidation | Password, role, status, and grant changes invalidate affected sessions/tokens |
| OAuth | Mock/test OAuth impossible outside local/testing; production credentials configured |
| External access | Token/code/session expiry, revoke, throttling, operation scopes, and audit tests pass |
| Medical files | Private authorization, type/size validation, malware-scan policy, and safe download headers |
| SOS/alerts | Recipient, location, state-machine, acknowledge/resolve, and audit matrices pass |
| Authorization | Role, assistant-grant, object-type, object-target, and IDOR negative tests pass |
| Privacy/legal | Public privacy policy and terms explain health data, location/SOS, retention, deletion, and external sharing |
| Operations | Scheduler, queue worker, monitoring, backups, and incident response are supervised and tested |
| Real-time | Private-channel auth, WSS proxying, queue/Reverb supervision, reconnect, missed-event recovery, and multi-client tests pass |

### Inputs required from the application owner

The repository-side implementations and safe templates are complete. The
following cannot be fabricated or approved by engineering. Put secrets in the
deployment secret manager or ignored configuration files—not in chat, commits,
screenshots, tickets, or the README.

1. **Production identity and hosting:** final `app.` and `api.` domains,
   hosting/region, Linux/PHP-FPM paths, TLS/DNS control, production database and
   Redis endpoints, and the staff member who can install Nginx/systemd units.
2. **Firebase/APNs:** Firebase project ID, backend service-account JSON, web app
   config, VAPID public key, registered Android/iOS app IDs, and an APNs `.p8`
   key with Apple Team ID and Key ID uploaded through the approved secret path.
3. **Google authentication:** production web client ID/secret/redirect URI,
   Android client registration with release SHA-1/SHA-256 fingerprints, iOS
   client ID, and its reversed callback ID.
4. **Apple authentication/signing:** Apple Team ID, confirmed bundle ID,
   Services ID, HTTPS return URL/domain association, active Developer Program
   membership, signing certificates/profiles, and private-relay email-domain
   configuration where email is sent.
5. **Transactional email:** chosen SMTP/SES provider, host/port/encryption,
   secret credentials, approved from address/name, and DNS evidence for SPF,
   DKIM, and DMARC plus bounce/complaint handling.
6. **SMS password recovery:** Twilio Account SID, Auth Token, approved
   E.164-capable sender/phone number, the deployment's digits-only default
   country code, destination-country messaging permissions, and an owner for
   delivery/failure monitoring.
7. **Durable files:** S3-compatible endpoint/region/bucket, restricted runtime
   credentials, KMS/encryption decision, private bucket/CORS/lifecycle policy,
   malware-scanning service, and retention/deletion rules.
8. **Mobile releases:** approval of the permanent Android application ID and
   iOS bundle ID, Android upload keystore/alias/passwords, Apple signing access,
   store accounts, support URLs, screenshots, and an explicit supported-OS
   baseline. Minimum OS versions must not be raised without product/device
   approval.
9. **Reliability policy:** monitoring/error-tracking destination and alert
   contacts, log retention, incident escalation owner, backup destination,
   encryption key, retention, and approved RPO/RTO.
10. **Human acceptance:** named clinical/product owners and representative
   patient, doctor, admin, assistant, and external-clinician UAT testers;
   accessibility devices/assistive technologies; target concurrency and data
   volume for load testing.
11. **Privacy/legal approval:** approved privacy policy, terms, consent and
    external-sharing wording, health/location/SOS disclosures, account/data
    deletion process, retention schedule, subprocessors, jurisdiction, breach
    contact, and store privacy declarations.

No production cohort receives the redesigned workflow until its relevant gates are green.

---

## 11. Safe implementation and old-design retirement

The desired end state contains only the PDF-approved runtime design. Safe delivery is additive first and subtractive only after proven parity.

### Phase 0 — baseline and freeze

- Export the 110-route manifest and 197-route API inventory.
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
| Realtime | Private-channel auth, domain invalidations, all subscription confirmation, reconnect, missed event, REST fallback |

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
| `ALLOW_MOCK_SOCIAL_LOGIN` | Disabled by default everywhere; opt in only for an isolated local patient demo. Staff mock sign-in is rejected server-side |
| `MCARE_ALLOW_DEMO_SEED` | Keep `false` in production. A separate explicit override is required before synthetic accounts/clinical records can be seeded into a production environment |
| `MAIL_*` | Real SMTP/SES for production messages |
| `SMS_DRIVER`, `SMS_DEFAULT_COUNTRY_CODE` | Use `log` locally; production uses `twilio` and a digits-only country code such as `256` |
| `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_FROM_NUMBER` | Production SMS password-reset delivery; keep all values in the secret manager |
| `MCARE_SESSION_TOKEN_MINUTES`, `MCARE_REMEMBER_TOKEN_MINUTES` | Short and remembered Sanctum token lifetimes; defaults are 480 and 43,200 minutes |
| `MCARE_MAX_DEVICE_SESSIONS` | Maximum active Sanctum device tokens per account; default 10 |
| `MCARE_RESET_TOKEN_MINUTES`, `MCARE_RESET_OTP_MINUTES` | Email reset-grant and SMS OTP lifetimes; defaults are 60 and 10 minutes |
| `GOOGLE_CLIENT_*` | Production Google OAuth client and callback |
| `MCARE_ALLOWED_RETURN_HOSTS` | Allow-list for post-OAuth return hosts |
| `APPLE_CLIENT_ID` | Production Apple configuration if shipped |
| `FCM_*` | Firebase project/service-account values if push is shipped |
| `FILESYSTEM_DISK` | Private local storage or S3 |
| `AWS_*` | S3/SES credentials and region when AWS is used |

### Flutter dart-defines

| Define | Purpose |
|---|---|
| `MCARE_USE_BACKEND` | `true` for every normal build; `false` only for isolated UI work |
| `MCARE_ALLOW_DEMO_DATA` | Defaults to `false`; must accompany `MCARE_USE_BACKEND=false` before legacy in-memory fixtures activate |
| `MCARE_API_URL` | Laravel `/api/v1` base URL |
| `MCARE_WS_URL` | Optional Reverb WebSocket root |
| `MCARE_WS_APP_KEY` | Reverb application key paired with `MCARE_WS_URL` |
| `MCARE_GOOGLE_CLIENT_ID` | Google web OAuth client |
| `MCARE_GOOGLE_SERVER_CLIENT_ID` | Web client used as native backend audience |
| `MCARE_GOOGLE_IOS_CLIENT_ID` | Google iOS OAuth client |
| `MCARE_APPLE_CLIENT_ID`, `MCARE_APPLE_REDIRECT_URI` | Apple web OAuth values |
| `MCARE_FIREBASE_PROJECT_ID`, `MCARE_FIREBASE_MESSAGING_SENDER_ID` | Firebase values shared by every registered app in the project |
| `MCARE_FIREBASE_WEB_*`, `MCARE_FIREBASE_ANDROID_*`, `MCARE_FIREBASE_IOS_*` | Platform-specific Firebase API keys/app IDs; generic `MCARE_FIREBASE_API_KEY` and `MCARE_FIREBASE_APP_ID` remain backward-compatible fallbacks |
| `MCARE_FIREBASE_AUTH_DOMAIN`, `MCARE_FIREBASE_STORAGE_BUCKET`, `MCARE_FIREBASE_MEASUREMENT_ID`, `MCARE_FIREBASE_VAPID_KEY` | Web Firebase metadata and public web-push key |

Copy `frontend/config/app_config.example.json` to an ignored environment file,
for example `config/app_config.local.json`, fill only the public frontend values,
then run or build with
`--dart-define-from-file=config/app_config.local.json`. Backend secrets belong
only in `backend/.env`/the deployment secret manager. The ignore rules cover
local/production app-config files, Firebase service accounts, platform Firebase
files, signing keys, and the deployed web Firebase configuration.

### Provider credential acquisition checklist

Never paste private keys, passwords, service-account JSON, signing files, or
provider auth tokens into chat, tickets, the frontend JSON, or Git. Share them
through the approved secret manager. Public client identifiers/API metadata may
be placed in the frontend define file but should still have platform/domain/API
restrictions.

#### 1. Google Sign-In — required for the Google button

Use one Google Cloud project with separate OAuth clients for each platform.
Configure the OAuth consent/branding screen, support email, approved domains,
privacy policy, and terms before production. Official setup:
[Google Identity Services web setup](https://developers.google.com/identity/gsi/web/guides/get-google-api-clientid)
and [Google Cloud credentials](https://console.cloud.google.com/apis/credentials).

- **Web client:** obtain client ID and client secret. Add
  `http://localhost:8090` and the production Flutter origin to Authorized
  JavaScript origins. Register the exact backend callback from
  `GOOGLE_REDIRECT_URI` as an authorized redirect URI.
- **Android client:** register package `com.tattuintel.mcare` with debug and
  production signing SHA-1/SHA-256 fingerprints. This console registration is
  required even though its client ID is not stored as a Laravel secret.
- **iOS client:** register the final bundle ID, obtain the iOS client ID and
  reversed URL-scheme value.
- Put the web values in backend `.env` as `GOOGLE_CLIENT_ID`,
  `GOOGLE_CLIENT_SECRET`, and `GOOGLE_REDIRECT_URI`; set
  `MCARE_ALLOWED_RETURN_HOSTS` to the exact frontend hosts.
- Put the same web ID in frontend `MCARE_GOOGLE_CLIENT_ID` and
  `MCARE_GOOGLE_SERVER_CLIENT_ID`; put the iOS ID in
  `MCARE_GOOGLE_IOS_CLIENT_ID`. Copy
  `frontend/ios/Flutter/Secrets.xcconfig.example` to ignored
  `Secrets.xcconfig` and set `GOOGLE_REVERSED_CLIENT_ID`.

#### 2. Firebase Cloud Messaging — required for background push

Create one Firebase project and register Web, Android
(`com.tattuintel.mcare`), and iOS (the final bundle ID) apps. The official
[FlutterFire setup](https://firebase.google.com/docs/flutter/setup) and
[FCM Flutter setup](https://firebase.google.com/docs/cloud-messaging/flutter/get-started)
cover platform registration, APNs, VAPID, and device testing.

- From Project settings → General collect project ID, messaging sender ID,
  storage bucket/auth domain, and each platform's API key and app ID. Fill the
  matching `MCARE_FIREBASE_*` entries in the frontend app-config file.
- For web, generate a Web Push certificate and place its **public** VAPID key in
  `MCARE_FIREBASE_VAPID_KEY`. Copy
  `frontend/web/firebase-config.example.json` to ignored
  `frontend/web/firebase-config.json` with the web app metadata.
- From Project settings → Service accounts generate the backend HTTP-v1 JSON,
  store it outside the public tree, and set `FCM_PROJECT_ID` plus the standard
  `GOOGLE_APPLICATION_CREDENTIALS` path. `FCM_SERVICE_ACCOUNT_PATH` is a
  supported local fallback.
- For Apple background delivery, create an APNs `.p8` key and upload it to
  Firebase with its Key ID and Apple Team ID. Keep Push Notifications and
  Background Modes enabled in the signed Xcode target.
- `google-services.json` and `GoogleService-Info.plist` remain ignored. They may
  be generated by `flutterfire configure`; this repository can also initialize
  Firebase explicitly from the platform-specific dart-defines.

#### 3. Google Maps and location — universal fallback plus embedded map

The application captures consented/SOS device location through `geolocator`,
resolves a human-readable label through the platform geocoder, and opens Google
Maps search or directions on web, Android, and iOS. These universal URLs remain
the fail-safe and require no key. Patient-chart and SOS-response views also show
an embedded `google_maps_flutter` map when `MCARE_GOOGLE_MAPS_ENABLED=true` and
the platform key is installed.

Enable Maps SDK for Android, Maps SDK for iOS, and Maps JavaScript API. Use
separate application-restricted keys: Android package/signing fingerprints,
iOS bundle ID, and web HTTPS referrers. Android reads `MAPS_API_KEY` from ignored
`android/local.properties`; iOS reads `GOOGLE_MAPS_API_KEY` from ignored
`Flutter/Secrets.xcconfig`; web reads the public restricted key from
`MCARE_GOOGLE_MAPS_WEB_API_KEY` and loads the SDK only when a map is displayed.
Follow [Google Maps for Flutter setup](https://developers.google.com/maps/flutter-package/config).

The focused end-to-end console, credential, database, build, and smoke-test
sequence is in
[`docs/FIREBASE_GOOGLE_DATABASE_SETUP.md`](docs/FIREBASE_GOOGLE_DATABASE_SETUP.md).

#### 4. Sign in with Apple — required for the Apple button

In the Apple Developer portal, enable Sign in with Apple for the final App ID,
create a web Services ID, associate the primary App ID, register the production
domain and exact HTTPS return URL, and enable the Xcode capability. See
[Apple native configuration](https://developer.apple.com/documentation/xcode/configuring-sign-in-with-apple)
and [Apple web configuration](https://developer.apple.com/documentation/signinwithapple/configuring-your-webpage-for-sign-in-with-apple).

- Set backend `APPLE_CLIENT_ID` to the accepted audience list (web Services ID
  and native bundle ID where both ship).
- Set frontend `MCARE_APPLE_CLIENT_ID` to the Services ID and
  `MCARE_APPLE_REDIRECT_URI` to the registered HTTPS return URL.
- Provide Apple Team ID, App/Services IDs, signing team/profiles, and relay-email
  domain setup. The current identity-token/nonce flow does not require placing
  a Sign in with Apple private key in the client.

#### 5. SMS password recovery — required for real phone OTP delivery

Create a Twilio account, obtain an SMS-capable sender and enable destination
country permissions. Twilio's
[Messaging quickstart](https://www.twilio.com/docs/messaging/quickstart) lists
the Account SID/Auth Token/sender steps; recipients must be E.164 numbers.

- Backend only: `SMS_DRIVER=twilio`, `SMS_DEFAULT_COUNTRY_CODE=256` (or the
  deployment's digits-only default), `TWILIO_ACCOUNT_SID`,
  `TWILIO_AUTH_TOKEN`, and `TWILIO_FROM_NUMBER`.
- Trial Twilio accounts deliver only to verified recipients. Production testing
  must cover real carriers, delivery failures, throttling, and monitored costs.

#### 6. Transactional email — required for links, verification, and invites

Choose a production SMTP provider. Supply `MAIL_MAILER=smtp`, `MAIL_SCHEME`,
`MAIL_HOST`, `MAIL_PORT`, `MAIL_USERNAME`, `MAIL_PASSWORD`, `MAIL_TIMEOUT`,
`MAIL_FROM_ADDRESS`, and `MAIL_FROM_NAME`. Approve the sender/domain and publish
SPF, DKIM, and DMARC records. Amazon documents that
[SES SMTP credentials are different from AWS access keys](https://docs.aws.amazon.com/ses/latest/dg/smtp-credentials.html).
Gmail app passwords are acceptable only for controlled development, not the
recommended production mail architecture.

#### 7. Reverb real-time transport — application-generated credentials

Reverb does not require a third-party API account. Generate strong independent
`REVERB_APP_ID`, `REVERB_APP_KEY`, and `REVERB_APP_SECRET` values server-side;
set `BROADCAST_CONNECTION=reverb`, host/port/scheme, allowed origins, and a
supervised WSS process. Only the app key is copied to frontend
`MCARE_WS_APP_KEY`; the app secret never enters Flutter. See
[Laravel Reverb configuration](https://laravel.com/docs/12.x/reverb).

#### 8. Database, Redis, storage, domains, and signing

- MySQL: dedicated database/host/port, least-privilege username/password, TLS,
  encrypted backup destination, and a restore-tested retention policy.
- Redis at production scale: host, port, password/TLS, then use Redis for queue,
  cache, and multi-instance sessions.
- Private S3-compatible storage: `AWS_ACCESS_KEY_ID`,
  `AWS_SECRET_ACCESS_KEY`, `AWS_DEFAULT_REGION`, `AWS_BUCKET`, optional endpoint,
  private bucket policy, encryption/KMS, CORS, lifecycle, malware scanning, and
  authorized download tests. Use a least-privilege workload identity/role where
  the hosting platform supports it instead of long-lived keys.
- Domains/TLS: final HTTPS API/frontend domains, DNS control, CORS/Sanctum
  origins, WSS proxy, privacy/terms/support URLs, and `APP_DEBUG=false`.
- Android: copy `frontend/android/key.properties.example` to ignored
  `key.properties` and provide the upload keystore, alias, store password, and
  key password. iOS requires the final bundle ID, Apple team, distribution
  certificate/profile, App Store Connect access, and `APS_ENVIRONMENT`.

Android release signing uses `frontend/android/key.properties`; start from
`key.properties.example` and keep the real keystore/passwords out of version
control. Release tasks now fail if this file is absent instead of silently
producing a debug-signed artifact. For iOS Google callbacks, copy
`frontend/ios/Flutter/Secrets.xcconfig.example` to `Secrets.xcconfig` and set
the reversed iOS client ID; the real file is ignored.

### Integration status

- **Laravel Sanctum:** active for bearer-authenticated REST and broadcast
  authorization. Role middleware and object/caseload checks remain server-side.
- **Laravel Reverb/Pusher protocol:** implementation complete and opt-in. It is
  inactive when credentials are absent or the broadcaster is `log`/`null`, so
  local/demo environments do not accumulate useless broadcast queue jobs.
- **Firebase Cloud Messaging:** token registration, HTTP-v1 server delivery,
  service-account validation, invalid-token cleanup, web background worker,
  iOS entitlement, and Android high-importance channel exist; real
  service-account/VAPID/APNs/mobile permission testing is still required.
- **Email:** verification, OTP, password recovery, invite, credentials, and
  consent paths share one synchronous audited dispatcher. Authenticated flows
  report transport failure instead of claiming a message was sent; provider
  bounce/suppression monitoring remains an operational requirement.
- **SMS:** phone password recovery uses canonical E.164 lookup and Twilio's
  Messages API in production. The `log` driver is development-only; real
  carrier delivery and sender/country permissions remain owner-supplied gates.
- **Google/Apple:** web OAuth, native Flutter SDK adapters, backend token
  verification, multi-audience Apple validation, and fail-closed production
  behavior exist. Platform console IDs, iOS callback scheme, signing, and
  real-device verification remain owner-supplied gates. Mock social login and
  in-memory identities require separate explicit local-development opt-ins.
- **Geolocation/geocoding:** client packages support SOS/location capture and
  remain subject to platform permissions and privacy disclosure.
- **File storage:** Laravel filesystem abstraction supports private local/S3
  storage. Production still needs bucket policy, signed delivery, scanning,
  lifecycle, and restore validation.
- **External Clinical Access:** patient-owned expiring/revocable tokens and
  codes, guest record scope, uploads/notes, audit, token-scoped private Reverb
  channel, REST reconciliation, and lifecycle/authorization tests exist.
- **Redis:** optional and recommended for scaled queue/cache/session workloads;
  the verified local environment uses database drivers.

---

## 14. Deployment

### Recommended production shape

Ready-to-customize Nginx, systemd, k6, monitoring, backup/recovery, and rollback
material is maintained in [`deploy/`](deploy/README.md). The repository checks
configuration without revealing secrets:

```bash
cd backend
php artisan mcare:readiness
php artisan mcare:readiness --strict --json
```

| Concern | Suggested service | Requirement |
|---|---|---|
| Laravel API | AWS Lightsail/EC2 or equivalent | Web root is `backend/public`; HTTPS only |
| MySQL | RDS/Lightsail managed MySQL | Private network, backups, restore rehearsal |
| Queue/cache | Redis/ElastiCache at production scale | Supervised queue workers |
| Reverb | Supervised process behind Nginx/ALB | WSS upgrade headers and private-channel auth |
| Files | Private S3 bucket | Encryption, signed/authorized delivery, lifecycle policy |
| Email | Amazon SES or approved SMTP | Production sending access and monitored failures |
| SMS | Twilio or an approved equivalent adapter | E.164 sender, country permissions, delivery/failure monitoring |
| Flutter web | S3 + CloudFront or web server | SPA fallback to `index.html`, including `/external?token=…` |
| DNS/TLS | Route 53 + ACM or equivalent | `api.` and `app.` HTTPS domains |
| Monitoring | Application/error/log monitoring | Alerts for 5xx, job failures, WebSocket failure, and backup failure |

### Recommended deployment plan

1. **Provision staging first:** use production-equivalent HTTPS, MySQL, Redis,
   private object storage, SMTP sandbox, Reverb/WSS, queue/scheduler supervisors,
   and monitoring. Keep it isolated from live patient data.
2. **Deploy and migrate:** install locked dependencies, inject secrets through
   the platform secret manager, run `mcare:readiness --strict`, migrate forward,
   build Flutter with production-like defines, and verify `/ready`.
3. **Install staging test data only:** run `migrate:fresh --seed`, then
   `mcare:demo-status --strict`. Keep `MCARE_ALLOW_DEMO_SEED=false` in production
   and never run `db:seed` or `migrate:fresh` against the live database.
4. **Exercise event delivery:** connect patient and staff clients, run each
   `mcare:simulate` scenario, verify private-channel scoping, push/email delivery,
   REST reconciliation, alert acknowledgement/resolution, and zero failed jobs.
5. **Prove operations:** execute the k6 profile at the approved concurrency,
   restore an encrypted backup into an isolated database, test WSS reconnect and
   queue-worker restart, complete accessibility/clinical UAT, and close P0/P1s.
6. **Production cutover:** take/verify a backup, deploy code, run only
   `php artisan migrate --force`, warm caches, restart supervised workers, smoke
   the real domains, release to a small cohort, monitor, then expand. Roll back
   application code without reversing schema unless the tested rollback runbook
   explicitly permits it.

### Laravel deployment sequence

```bash
cd /var/www/mcare/backend
composer install --no-dev --optimize-autoloader
php artisan mcare:readiness --strict
php artisan migrate --force
php artisan storage:link
php artisan config:cache
php artisan route:cache
```

The production sequence intentionally has no seeder command. Synthetic records
belong only in local, CI, demonstration, and isolated staging databases.

Use the units under `deploy/systemd/` (or an equivalent process manager). Keep
Reverb on loopback and expose it only through the TLS reverse proxy:

```bash
php artisan queue:work --tries=3
php artisan reverb:start --host=127.0.0.1 --port=8080
php artisan schedule:work
```

The cron alternative to the supervised scheduler is:

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
flutter.bat build appbundle --release `
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
| `dr.kamau@mcare.health` | Pending doctor approval workflow |
| `dr.wanjiru@mcare.health` | Pending doctor approval workflow |
| `amara.okonkwo@example.com` | Patient with a rich demonstration chart |
| `brian.otieno@example.com` | Patient — stable asthma/normal readings |
| `wangari.njeri@example.com` | Patient — post-stroke/critical workflow |
| `daniel.mwangi@example.com` | Patient — wellness monitoring |
| `esther.wambui@example.com` | Patient — hypertension/warning workflow |

Every active patient has API-backed contacts, care assignment, history,
medication/dose, past and future appointments, a downloadable fixture document,
conversation/message, notifications, support, meal plan, and report work. The
patients collectively cover normal/warning/critical vitals, pending/fulfilled
vital reports, report consent/signature/issued/declined/draft states, active and
resolved SOS work, and external access.

Demo credentials are synthetic development data only. The production guard
rejects this dataset unless `MCARE_ALLOW_DEMO_SEED=true` is deliberately set;
the deployment plan keeps that value false and never runs a production seeder.

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
