# mCare — Remote Patient Monitoring Platform

**mCare** is a full-stack Remote Patient Monitoring (RPM) and healthcare-management platform. Patients record vitals at home; the backend classifies readings against clinical thresholds; care providers respond through alerts, messaging, appointments, prescriptions, reports, and emergency SOS. Administrators and delegated **mCare Assistants** run the platform. Patients can mint **time-limited external-doctor links** so outside clinicians can work on the chart from the web.

**Stack:** Laravel 12 REST API (`backend/`) · Flutter 3 (`frontend/`, web + Android + iOS + Windows) · MySQL  
**Last audited:** 2026-07-22 — this document is the single source of truth.

> **Golden rule:** Build once, use everywhere. One app, one design language, one component library, one notification pipeline. Role changes **content and accent colour** — not duplicate screens.

---

## Table of contents

1. [Audit summary (done / pending / missing)](#audit-summary-done--pending--missing)
2. [Quick start](#quick-start)
3. [Architecture](#architecture)
4. [Routes & navigation (all roles)](#routes--navigation-all-roles)
5. [External doctor access (temp links)](#external-doctor-access-temp-links)
6. [User roles & assistant permissions](#user-roles--assistant-permissions)
7. [Feature status](#feature-status)
8. [API reference](#api-reference)
9. [Database schema](#database-schema)
10. [Demo accounts](#demo-accounts)
11. [Environment & configuration](#environment--configuration)
12. [Host on Amazon (AWS)](#host-on-amazon-aws)
13. [Google Play Store](#google-play-store)
14. [Apple App Store](#apple-app-store)
15. [Improvements roadmap](#improvements-roadmap)
16. [License](#license)

---

## Audit summary (done / pending / missing)

_Re-verified against code on 2026-07-22._

### At-a-glance metrics

| Layer | Metric | Count |
|-------|--------|-------|
| Backend routes | `Route::(get\|post\|put\|patch\|delete)` in `routes/api.php` | **140** |
| Backend controllers | `app/Http/Controllers/Api/V1/` + `.../V1/Admin/` | **50** |
| Backend models | `app/Models/*.php` | **34** |
| Backend migrations | `database/migrations/` | **19** |
| Backend feature tests | `tests/Feature/` (excl. Example) | **2+** |
| Frontend `RouteNames` | Named route constants | **99** |
| Frontend `main.dart` wired cases | Every `RouteNames.*` has a switch case | **99 / 99** |
| Frontend API clients | `lib/core/api/*.dart` | **25** |
| Frontend state stores | `lib/shared/state/*.dart` | **14** |

### ✅ Done — product & code complete

| Area | Status |
|------|--------|
| Auth (email/password, Google web, Apple wired, forgot/reset, OTP, invites) | Done |
| Force-change password (patient + all staff) | Done — `*ForcePassword` routes |
| Voluntary change password (all roles via `ChangePasswordSheet`) | Done — single Security section (no patient duplicate) |
| Patient onboarding (health profile) | Done — replaces any `patientCompleteProfile` idea |
| All role routes wired, no orphans / no duplicates in `RouteNames` | Done |
| NotificationBell role-aware default | Done — uses `ProfileNavigation.notificationsRouteFor` |
| Patient external access create / share / revoke | Done — Care Team + Settings → Privacy |
| External portal: vitals, notes, **medications**, **document upload** | Done |
| SOS (patient + staff hubs) | Done — dashboard / profile / alerts (not forced into bottom nav) |
| Android release signing hook (`key.properties`) | Done |
| Brand launcher icons (Android / iOS / Web) | Done |

### ⚠️ Partial — works with caveats

| Area | Reality | Action |
|------|---------|--------|
| Staff notification *content* | Some `staff_*` items are computed client-side; read/resolve **is** persisted | Optional: server-side feed table |
| Native document open/download | Web works; Android/iOS no-op | Add `path_provider` + `open_filex` |
| `flutter test` on this Windows sandbox | Can hang; `flutter analyze` is reliable | Run tests in CI |
| Bottom nav omits Notifications & SOS | Reachable via header bell + dashboard / profile | Optional 6th tab or SOS FAB |

### 🚫 Blocked on credentials / infra (code ready)

| Item | What's missing |
|------|----------------|
| Production HTTPS host | AWS (or other) server + TLS + MySQL |
| SMTP | Real `MAIL_*` (SES / Gmail app password) |
| FCM push | Firebase project + service account + dart-defines + `firebase-messaging-sw.js` |
| Apple Sign-In live | Apple Developer Services ID + env vars |
| Native Google/Apple plugins | Device testing + plugin wiring |
| Play / App Store listings | Developer accounts, privacy policy URL, store assets |

### Intentionally absent (not bugs)

| Item | Why |
|------|-----|
| `patientCompleteProfile` route | Patients complete health data via **`patientOnboarding`**. Staff use `*CompleteProfile`. |
| Notifications / SOS as patient bottom-nav tabs | UX choice — 5 primary tabs. Entry points exist. Add a tab or FAB only if product wants one-tap from every screen. |
| Separate external-doctor account | External clinicians are **token guests**, not registered users. |

### 🔴 P0 before real patients

1. Host API + DB on HTTPS with `APP_DEBUG=false`, dedicated MySQL user, automated backups.  
2. Real SMTP so OTP / reset / invite emails send.  
3. Privacy policy + terms URLs (required by Play Store & App Store for health apps).  
4. Expand tests: auth/lockout, SOS, external-access create→vitals/meds/docs→revoke.

---

## Quick start

You need **two** processes: Laravel API + Flutter web.

### 1. Backend

```bat
cd backend
composer install
copy .env.example .env
php artisan key:generate
php artisan migrate --seed
php artisan storage:link
php artisan serve --port=9090
```

API: `http://127.0.0.1:9090/api/v1`

Production scheduler (SLA escalation):

```
* * * * * cd /path/to/backend && php artisan schedule:run >> /dev/null 2>&1
```

### 2. Frontend (live API)

```bat
cd frontend
flutter pub get
flutter run -d web-server --web-hostname localhost --web-port 8090 ^
  --dart-define=MCARE_USE_BACKEND=true ^
  --dart-define=MCARE_API_URL=http://127.0.0.1:9090/api/v1
```

Open `http://localhost:8090`.

### Demo mode (no backend)

```bat
flutter run -d web-server --web-hostname localhost --web-port 8090 ^
  --dart-define=MCARE_USE_BACKEND=false
```

---

## Architecture

```
mcares3/
├── backend/            Laravel 12 REST API → /api/v1/*
│   ├── routes/api.php
│   ├── app/Http/Controllers/
│   ├── app/Services/          Audit, FCM, SOS, VitalAlert
│   ├── app/Models/
│   └── database/              migrations + seeders
├── frontend/           Flutter (web + mobile + desktop)
│   └── lib/
│       ├── patients/ doctors/ admin/ mcare_assistant/
│       ├── auth/              login, register, external portal
│       ├── core/              API, env, poller, push, mock
│       └── shared/            UI, state, theme, navigation
├── resources/          Branding assets
└── README.md           This file (canonical docs)
```

**Real-time:** no WebSocket. `SessionPoller` hits role session endpoints every **30 s** (8 s during SOS). Mutations hit REST immediately; the poller reconciles.

**Import rule:** `shared/` never imports role folders (0 violations).

---

## Routes & navigation (all roles)

Routing uses Flutter **named routes** (`MaterialApp.onGenerateRoute` in `main.dart`), not GoRouter.  
**Source of truth:** `frontend/lib/shared/constants/route_names.dart` — **99 constants, all wired**.

### Pre-login / shared

`/`, `/home`, `/login`, `/register`, `/verify-email`, `/forgot-password`, `/reset-password`, `/pending-approval`, `/accept-invite`, `/external`

### Patient

| Route | Purpose |
|-------|---------|
| `/patient/onboarding` | Health-profile onboarding (not a separate “complete profile”) |
| `/patient` … vitals / meds / appointments / documents / messages / care-team | Core tabs & features |
| `/patient/notifications` | Inbox (header bell) |
| `/patient/profile`, `/patient/settings`, `/patient/support` | Account |
| `/patient/force-password` | Admin-issued temp password gate |
| `/patient/sos` | Emergency SOS |

**Bottom nav (5):** Home · Vitals · Meds · Visits · Chat  
Desktop rail also exposes Profile + Settings.

### Doctor / Admin / Assistant

All `doctor*`, `admin*`, `assistant*` constants in `RouteNames` are registered — including `*CompleteProfile`, `*ForcePassword`, notifications, SOS hubs, messaging threads, and admin workspace screens.

Staff chrome uses `RoleShell` + `StaffDestinations` (permission-filtered for assistants). Notification routes come from `ProfileNavigation.notificationsRouteFor(role)`.

### Navigation hygiene (2026-07-22)

- **NotificationBell** no longer hardcodes the patient inbox; guests / external doctors with no inbox route are a no-op.  
- **`NavigationRoots`** includes `assistantPatients` and force-password / complete-profile roots so profile-menu navigation does not bounce.  
- **Patient profile** exposes Change password once (Security section only).

---

## External doctor access (temp links)

Patients create a **time-limited link + spoken code** so an outside clinician can use the **web portal** without an mCare account.

### Where patients manage links

1. **Settings → Privacy** — enable “External doctor access”, then **Create & share external link**.  
2. **My team (Care team) → Emergency access** — same sheet (create / copy / share / revoke).

Constraints: max **5** active links · expiry **24 h / 3 days / 7 days** · one-tap revoke · security audit on create/revoke · access codes use a no-lookalike alphabet; resolve-code throttled **6/min**.

### What the outside doctor can do on `/external`

| Action | API |
|--------|-----|
| Open via link `?token=` or access code | `POST /external/resolve-code`, `GET /external/{token}` |
| Review summary (allergies, conditions, recent vitals/meds/docs) | `GET /external/{token}` |
| Record vitals (same risk + care-team alert pipeline) | `POST /external/{token}/vitals` |
| Assign medication | `POST /external/{token}/medications` |
| Upload documents / reports (PDF, images, Word) | `POST /external/{token}/documents` |
| Submit consultation note | `POST /external/{token}/notes` |

Portal UI: `frontend/lib/auth/external_doctor_view.dart`  
Patient sheet: `frontend/lib/patients/care_team/external_access_sheet.dart`  
`FRONTEND_URL` in backend `.env` is used to build shareable links (`https://app…/external?token=…`).

---

## User roles & assistant permissions

| Role | Accent | Access |
|------|--------|--------|
| Patient | Indigo | Own chart, SOS, care team, external links, support |
| Doctor | Green | Caseload clinical tools + SOS |
| Admin | Purple | Full platform |
| mCare Assistant | Amber | Admin subset via 12 permission keys |
| External Doctor | Blue | Token portal only — no account |

Assistant permissions (`assistant_permissions` + `EnsurePermission`): approve health workers, care requests, assignments, create users, change roles, register admin/assistant, audit/analytics, security incidents, SOS location, announcements, vital catalog. Grants refresh live via session poller (≤ 30 s).

---

## Feature status

### Fully functional (backend-wired)

- **Auth & self-service:** login/register, Google (web), Apple (wired pending creds), forgot/reset, OTP, invites, avatar, email change + re-verify, specialty/licence (doctors), in-app password change, force password for all roles.  
- **Patient:** vitals, meds, appointments, documents, chat, notifications, SOS, support, care team, vital-report requests, external access.  
- **Doctor:** caseload, alerts, prescriptions, reports, appointments, chart, docs, meal plans, care requests, SOS, messaging, vital catalog.  
- **Admin / Assistant:** users, approvals, routing, assignments, permissions, announcements, audit, security, support, analytics, system, SOS, messaging.  
- **Cross-cutting:** `/me/settings`, staff notification read-state, SLA escalation cron, vital-alert auto-resolve.

### Partial

- Staff inbox *content* still partly client-derived.  
- Native (non-web) document preview/download.

### Credentials-gated

- FCM push, live Apple Sign-In, native OAuth plugins, store-signed release keystores.

---

## API reference

Base: `/api/v1`. Public: `/auth/*` (throttled), `/external/*`. Everything else: Sanctum bearer + role / permission middleware.

| Group | Prefix | Notes |
|-------|--------|-------|
| Auth | `/auth/*` | Login, register, OTP, profile, avatar, change-email/password |
| External | `/external/*` | resolve-code, show, notes, vitals, **medications**, **documents** |
| Me | `/me/settings`, `/me/notification-states` | Any authenticated role |
| Patient | `/patient/*` | Incl. `external-access` list/create/revoke |
| Doctor | `/doctor/*` | Caseload-scoped |
| Admin | `/admin/*` | Admin + assistant (+ `permission:*`) |

Full definitions: `backend/routes/api.php`.

---

## Database schema

19 migrations under `backend/database/migrations`. Core tables include `users`, health profiles, vitals, medications, appointments, `medical_documents`, chat, notifications, SOS, care coordination, `external_access_tokens`, audits, announcements, FCM tokens, settings.

Foreign keys cover owned data; `vital_key` string columns intentionally omit an FK so catalog deletes are not blocked by historical readings (documented trade-off).

---

## Demo accounts

After `php artisan migrate --seed` (password `demo-password`):

| Email | Role |
|-------|------|
| `admin@mcare.health` | Admin |
| `assistant@mcare.health` | Assistant (all permissions) |
| `dr.mensah@mcare.health` | Doctor |
| `dr.adeyemi@mcare.health` | Doctor (Endocrinology) |
| `amara.okonkwo@example.com` | Patient (rich demo chart) |
| Other `@example.com` patients | Caseload variety |

---

## Environment & configuration

### Backend (`backend/.env`)

| Variable | Production |
|----------|------------|
| `APP_ENV` / `APP_DEBUG` | `production` / **`false`** |
| `APP_URL` | `https://api.yourdomain.com` |
| `FRONTEND_URL` | `https://app.yourdomain.com` (builds external links) |
| `DB_*` | Dedicated MySQL user — never root |
| `MAIL_*` | Real SMTP (SES or Gmail app password) |
| `GOOGLE_CLIENT_*` | Production OAuth client + redirect |
| `APPLE_CLIENT_ID` | If shipping Sign in with Apple |
| `FCM_PROJECT_ID` + service account | If shipping push |
| `FILESYSTEM_DISK` | `local` (+ `storage:link`) or `s3` |
| `SANCTUM_STATEFUL_DOMAINS` + CORS origins | Your app domain(s) |

### Frontend dart-defines

| Define | Purpose |
|--------|---------|
| `MCARE_USE_BACKEND` | `true` for live API |
| `MCARE_API_URL` | `https://api.yourdomain.com/api/v1` |
| `MCARE_GOOGLE_CLIENT_ID` | Web Google OAuth |
| `MCARE_APPLE_*` | Sign in with Apple |
| `MCARE_FIREBASE_*` | Push (also fill `web/firebase-messaging-sw.js`) |

Android signing: `frontend/android/key.properties` (see `key.properties.example`).

---

## Host on Amazon (AWS)

Goal: HTTPS API for mobile apps + HTTPS web app for the external portal and browser users.

### Recommended minimal architecture

| Piece | AWS service | Notes |
|-------|-------------|-------|
| Laravel API | **Lightsail** ($5–12/mo LAMP/Ubuntu) or **EC2** | Docroot → `backend/public/` |
| MySQL | **Lightsail managed MySQL** or **RDS MySQL 8** | Automated backups (P0 for patient data) |
| HTTPS | Lightsail **Let's Encrypt** (`bncert-tool`) or ALB + **ACM** | Required for Android cleartext policy, OAuth, SOS GPS |
| DNS | **Route 53** (or any registrar) | `api.` + `app.` records |
| Files | Local disk first; later **S3** (`FILESYSTEM_DISK=s3`) | Avatars + medical documents |
| Email | **Amazon SES** (or Gmail SMTP to start) | SES needs production access out of sandbox |
| Flutter web | Same box under `/var/www/app` **or** **S3 + CloudFront** | SPA fallback: unknown paths → `index.html` |
| Optional CDN | CloudFront in front of API/web | Cache static assets only |

### Step-by-step (Lightsail path)

1. **Create instance** — Ubuntu 22.04 / LAMP blueprint, open ports 80/443 (and 22 for SSH).  
2. **Attach static IP** + point `api.yourdomain.com` A-record at it.  
3. **Create managed MySQL** — note host/user/password; create database `mcare`.  
4. **Install PHP 8.2+**, Composer, enable `php-mysql`, `php-mbstring`, `php-xml`, `php-curl`, `php-gd`, `php-zip`.  
5. **Deploy backend**
   ```bash
   cd /var/www/mcare-api
   composer install --no-dev --optimize-autoloader
   cp .env.example .env
   # edit .env: APP_ENV=production APP_DEBUG=false APP_URL DB_* FRONTEND_URL MAIL_*
   php artisan key:generate
   php artisan migrate --force
   php artisan storage:link
   php artisan config:cache && php artisan route:cache
   ```
6. **Apache/Nginx** — virtual host docroot = `backend/public`. Enable HTTPS (bncert or certbot).  
7. **CORS + Sanctum** — allow `https://app.yourdomain.com` (and mobile origins if needed).  
8. **Cron** — `* * * * * php artisan schedule:run`.  
9. **Queue** — `php artisan queue:work` under systemd/supervisor (or `QUEUE_CONNECTION=sync` temporarily).  
10. **Build & host Flutter web**
    ```bash
    cd frontend
    flutter build web --release \
      --dart-define=MCARE_USE_BACKEND=true \
      --dart-define=MCARE_API_URL=https://api.yourdomain.com/api/v1 \
      --dart-define=MCARE_GOOGLE_CLIENT_ID=...
    ```
    Upload `build/web` to the web vhost or S3+CloudFront. Keep SPA rewrite so `/external?token=…` deep links work.  
11. Set `FRONTEND_URL=https://app.yourdomain.com` so patient-shared external links are correct.  
12. Smoke-test: login as demo patient → create external link → open in private browser → record vital / assign med / upload PDF.

### Cost ballpark (testing)

Lightsail instance + managed DB ≈ **$15–40/mo**. Add SES, Route 53, and S3 as you harden.

---

## Google Play Store

### Prerequisites

1. [Google Play Console](https://play.google.com/console) account ($25 one-time) + identity verification.  
2. **Backend already on HTTPS** (phones cannot use `127.0.0.1`).  
3. Unique `applicationId` in `frontend/android/app/build.gradle.kts` (immutable after first upload).  
4. Upload keystore:
   ```bat
   keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```
   Create `frontend/android/key.properties` from the example. **Back up the keystore — losing it blocks updates.**  
5. Privacy policy URL hosted publicly (health apps). Complete Data safety, content rating, Health apps declaration.

### Build

```bat
cd frontend
flutter build appbundle --release ^
  --dart-define=MCARE_USE_BACKEND=true ^
  --dart-define=MCARE_API_URL=https://api.yourdomain.com/api/v1 ^
  --dart-define=MCARE_GOOGLE_CLIENT_ID=your-client-id
```

Output: `build/app/outputs/bundle/release/app-release.aab`.

Optional push: Firebase Android app + `google-services.json` under `android/app/`.

### Release track

1. Create app → **Internal testing** → upload AAB → add tester emails → share opt-in link.  
2. Bump `version` in `pubspec.yaml` (`1.0.1+2` — `+N` must increase every upload).  
3. Promote Internal → Closed → Open → Production. New personal developer accounts often need 12+ closed testers for 14 days before production.

Google Sign-In on Android also needs an Android OAuth client with package name + SHA-1 (upload key and Play App Signing certificate).

---

## Apple App Store

### Prerequisites

1. **Apple Developer Program** ($99/year).  
2. Mac with latest **Xcode**.  
3. Bundle ID (e.g. `com.tattuintel.mcare`) registered in Certificates, Identifiers & Profiles.  
4. App Store Connect app record + privacy nutrition labels (health data, location for SOS).  
5. Privacy policy URL.  
6. Backend on HTTPS reachable from devices.  
7. If using Sign in with Apple: enable capability on the App ID; set `APPLE_CLIENT_ID` / `MCARE_APPLE_*`.

### Build & upload

```bash
cd frontend
flutter build ipa --release \
  --dart-define=MCARE_USE_BACKEND=true \
  --dart-define=MCARE_API_URL=https://api.yourdomain.com/api/v1
```

Or open `frontend/ios/Runner.xcworkspace` in Xcode → set Team / signing → Product → Archive → Distribute App → App Store Connect.

Optional push: Firebase iOS app + `GoogleService-Info.plist`, enable Push Notifications + Background Modes.

### TestFlight → App Store

1. Upload build → process in App Store Connect.  
2. Add **TestFlight** internal/external testers.  
3. Prepare listing: screenshots (6.7" + 6.1" iPhones minimum), description, keywords, support URL, age rating.  
4. Submit for review. Health / medical apps get extra scrutiny — be clear that mCare is a **monitoring / coordination** tool, not a device that diagnoses or replaces emergency services. Document SOS + external-access behaviour in the review notes.

---

## Improvements roadmap

### P0 — before real patients

1. HTTPS hosting + hardened `.env` + DB backups.  
2. SMTP credentials.  
3. Privacy policy + terms.  
4. Broader automated tests on auth, SOS, external access (vitals/meds/docs), med dosing.

### P1 — reliability

5. Queue FCM fan-out.  
6. Indexes: `vital_readings(user_id, recorded_at)`, `app_notifications(user_id, read)`, `chat_messages(conversation_id, created_at)`.  
7. Turn on FCM to replace 30 s polling for alerts.  
8. Error monitoring (Sentry free tiers for Laravel + Flutter).

### P2 — product depth

9. Optional PIN on external access; patient “who accessed my record” UI.  
10. Offline cache for last-known dashboard.  
11. Native document preview/download.  
12. Localization beyond English.  
13. Optional: Notifications / SOS as bottom-nav tab or persistent SOS FAB.

---

## License

Private — all rights reserved. Not licensed for public distribution.
