# Firebase, Google Services, Maps, and Database Setup

This is the production-oriented setup path for mCare. Complete it first in an
isolated staging project, then repeat it for production with separate keys and
domains.

## 1. Keep the architecture simple

Use Laravel and MySQL as the only source of truth for users, clinical records,
permissions, audit history, settings, and workflow state. Firebase is used only
for Cloud Messaging device delivery. Do not enable Firestore or Realtime
Database for application records: doing so would duplicate authorization and
clinical data, add another backup/retention surface, and make missed updates
harder to reconcile.

The application reads canonical data through the authenticated Laravel API.
Reverb sends PHI-free invalidation signals, and FCM wakes/notifies a device with
generic lock-screen text. After opening, the app fetches the authorized record
from Laravel.

## 2. Create the Google/Firebase project

1. Create one staging Google Cloud project and attach billing.
2. Add Firebase to that project.
3. In Google Cloud APIs & Services, enable:
   - Firebase Cloud Messaging API
   - Maps SDK for Android
   - Maps SDK for iOS
   - Maps JavaScript API
4. Configure the OAuth consent screen with the support email, verified domains,
   privacy policy, and terms URL.
5. Repeat with a separate production project before launch. Never share staging
   service-account keys with production.

## 3. Register Firebase applications

In Firebase Project settings → General, register these applications:

1. Web: the final HTTPS app origin.
2. Android: package `com.tattuintel.mcare`.
3. iOS: bundle ID `com.tattuintel.mcare` (or update the source and console
   together if the final bundle ID changes).

Collect the project ID, messaging sender ID, and each platform's API key and app
ID. Firebase web/API keys are public application identifiers, not server
secrets, but they must still be restricted to the intended APIs and
platform/domain.

Copy `frontend/config/app_config.example.json` to an ignored file such as
`frontend/config/app_config.staging.json`, then replace all applicable
`REPLACE_WITH_...` values. Do not leave placeholder text in a release file.

For web push:

1. Firebase Console → Project settings → Cloud Messaging → Web Push
   certificates → Generate key pair.
2. Put the public key in `MCARE_FIREBASE_VAPID_KEY`.
3. Copy `frontend/web/firebase-config.example.json` to the ignored
   `frontend/web/firebase-config.json` and fill the web Firebase metadata.
4. Serve the web app over HTTPS; browsers do not provide production push on an
   insecure origin.

For iOS push:

1. Enable Push Notifications, Background fetch, and Remote notifications for
   the signed Runner target in Xcode.
2. Create an APNs `.p8` authentication key in Apple Developer.
3. Upload it under Firebase Cloud Messaging with its Key ID and Apple Team ID.
4. Test on a physical iPhone; simulator success is not delivery evidence.

## 4. Configure secure backend FCM sending

Firebase Console → Project settings → Service accounts → Generate new private
key. Transfer the JSON through the deployment secret manager; never place it in
the web root, frontend configuration, Git, chat, or a ticket.

Set these backend environment values:

```dotenv
FCM_PROJECT_ID=your-firebase-project-id
GOOGLE_APPLICATION_CREDENTIALS=/run/secrets/firebase-service-account.json
FCM_REDACT_NOTIFICATION_CONTENT=true
FCM_TOKEN_TTL_DAYS=90
```

For local Windows development, an ignored path relative to `backend/` is also
supported:

```dotenv
FCM_PROJECT_ID=your-firebase-project-id
FCM_SERVICE_ACCOUNT_PATH=storage/app/firebase-service-account.json
```

The readiness audit verifies that the JSON is readable, is a service-account
file, and belongs to `FCM_PROJECT_ID`. HTTP v1 short-lived access tokens are
used; legacy FCM server keys are intentionally unsupported. Lock-screen text is
generic by default and device tokens older than the configured TTL are pruned.

## 5. Configure Google Sign-In

Create separate OAuth clients in Google Cloud Credentials:

1. Web client:
   - Authorized JavaScript origins: local `http://localhost:8090` and the final
     HTTPS frontend origin.
   - Authorized redirect URI: the exact backend
     `/api/v1/auth/google/callback` URL.
2. Android client:
   - Package `com.tattuintel.mcare`.
   - Add debug SHA-1/SHA-256 only to staging and release/upload SHA-1/SHA-256 to
     the production client.
3. iOS client:
   - Final bundle ID.
   - Record the iOS client ID and reversed URL scheme.

Backend-only values:

```dotenv
GOOGLE_CLIENT_ID=web-client.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=server-secret
GOOGLE_REDIRECT_URI=https://api.example.com/api/v1/auth/google/callback
MCARE_ALLOWED_RETURN_HOSTS=app.example.com
```

Frontend public values belong in the ignored app-config JSON:

```json
{
  "MCARE_GOOGLE_CLIENT_ID": "web-client.apps.googleusercontent.com",
  "MCARE_GOOGLE_SERVER_CLIENT_ID": "web-client.apps.googleusercontent.com",
  "MCARE_GOOGLE_IOS_CLIENT_ID": "ios-client.apps.googleusercontent.com"
}
```

On iOS, copy `frontend/ios/Flutter/Secrets.xcconfig.example` to ignored
`Secrets.xcconfig` and set `GOOGLE_REVERSED_CLIENT_ID`.

## 6. Configure Google Maps

Create three separate API keys in Google Cloud Credentials and restrict both
the application and APIs for every key.

### Android

1. Restrict the key to Android apps.
2. Add package `com.tattuintel.mcare` and the release certificate SHA-1.
3. Enable only Maps SDK for Android on this key.
4. Add this to ignored `frontend/android/local.properties`:

```properties
MAPS_API_KEY=your-android-restricted-key
```

### iOS

1. Restrict the key to iOS apps and the final bundle ID.
2. Enable only Maps SDK for iOS.
3. Add this to ignored `frontend/ios/Flutter/Secrets.xcconfig`:

```text
GOOGLE_MAPS_API_KEY=your-ios-restricted-key
```

The Maps package requires iOS 14+; the project deployment target is already set
accordingly. Run the iOS build from a supported macOS/Xcode host.

### Web

1. Restrict the key to Websites and list the exact staging/production HTTPS
   referrers, including the required path wildcard.
2. Enable only Maps JavaScript API.
3. Put the key in the frontend app-config as
   `MCARE_GOOGLE_MAPS_WEB_API_KEY`.

Finally set `MCARE_GOOGLE_MAPS_ENABLED` to `true` in the release app-config.
If any embedded SDK is unavailable, search and directions still open through a
key-free Google Maps URL on web, Android, and iOS.

## 7. Send real email and email OTPs immediately

mCare sends verification codes, reset links, invitations, temporary
credentials, and report-consent messages synchronously. The API waits for the
provider to accept the message, records a masked delivery event, and reports a
real failure for authenticated verification/resend actions. It does not put a
short-lived OTP behind a queue worker.

For controlled development, a Gmail account with 2-Step Verification and an
app password can be used:

```dotenv
MAIL_MAILER=smtp
MAIL_SCHEME=smtp
MAIL_HOST=smtp.gmail.com
MAIL_PORT=587
MAIL_USERNAME=sender@example.com
MAIL_PASSWORD=google-app-password
MAIL_TIMEOUT=10
MAIL_FROM_ADDRESS=sender@example.com
MAIL_FROM_NAME="mCare"
MAIL_REPLY_TO_ADDRESS=support@example.com
MAIL_SUPPORT_ADDRESS=support@example.com
```

For Resend SMTP, first verify a domain (prefer a dedicated subdomain such as
`updates.example.com`) and create a fresh sending API key. Configure Laravel
with the SMTP credential — the API key is the password, not the Resend account
password:

```dotenv
MAIL_MAILER=smtp
MAIL_SCHEME=smtp
MAIL_HOST=smtp.resend.com
MAIL_PORT=587
MAIL_USERNAME=resend
MAIL_PASSWORD=re_replace_with_a_fresh_api_key
MAIL_TIMEOUT=10
MAIL_FROM_ADDRESS=no-reply@updates.example.com
MAIL_FROM_NAME="mCare"
MAIL_REPLY_TO_ADDRESS=support@example.com
MAIL_SUPPORT_ADDRESS=support@example.com
```

The `MAIL_FROM_ADDRESS` domain must be one Resend has verified. If readiness
reports `Failed to authenticate`, rotate/create the Resend API key and replace
`MAIL_PASSWORD`; changing ports or the sender address will not repair an
invalid credential. Clear Laravel's cached configuration after every change.

Do not use the normal Gmail password. For production, prefer a transactional
provider with a verified domain, publish SPF, DKIM, and DMARC records, and keep
the SMTP/API credential in the deployment secret manager. A `log`, `array`, or
`null` mailer is deliberately treated as not delivered.

After changing environment values, verify without sending a message:

```bash
cd backend
php artisan config:clear
php artisan mcare:readiness --json
```

The `email` gate must say `pass` and `transport accepted credentials`. Then
send one branded delivery test to an inbox you control:

```bash
php artisan mcare:mail-test you@your-real-inbox.com
```

Only after that command reports `DELIVERED` should you register a staging
patient with the same inbox and verify that the
six-digit code arrives, expires, cannot be reused, and that resend creates a
new code. Check spam placement and provider suppression/bounce dashboards too.

## 8. Send real SMS OTPs immediately

The SMS recovery flow already creates a cryptographically random six-digit
code, stores only its password hash, expires it, burns it after five wrong
attempts, and sends within the recovery request. To enable the real Twilio
Messages API:

1. Create a Twilio project and obtain an SMS-capable sender.
2. Enable the destination countries required by the deployment.
3. For a trial project, verify every test destination first.
4. Add backend-only secrets:

```dotenv
SMS_DRIVER=twilio
SMS_DEFAULT_COUNTRY_CODE=256
TWILIO_ACCOUNT_SID=ACxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
TWILIO_AUTH_TOKEN=secret-manager-value
TWILIO_FROM_NUMBER=+1xxxxxxxxxx
```

Use the actual deployment country code (digits only) instead of `256` when the
service is not Uganda-based. Store user numbers in E.164 where possible. The
API regards Twilio's initial `queued`/`accepted` response as handed to the real
gateway; carrier delivery can still later fail, so monitor Twilio's delivery
dashboard and add signed status callbacks when delivery receipts become an
operational requirement. Never log OTP bodies in production.

Run `php artisan mcare:readiness --json`; `sms-recovery` must pass. Exercise a
password recovery against a verified staging handset and confirm that the OTP
arrives, is single-use, expires on schedule, and is replaced on resend.

## 9. Set up MySQL simply and securely

Use MySQL 8+ or MariaDB 10.6+. For a small single-server deployment, one
schema-scoped account is acceptable and much safer than `root`:

```sql
CREATE DATABASE mcare CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'mcare_app'@'APP_HOST' IDENTIFIED BY 'GENERATE_A_LONG_RANDOM_PASSWORD';
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, ALTER, INDEX, DROP, REFERENCES
  ON mcare.* TO 'mcare_app'@'APP_HOST';
FLUSH PRIVILEGES;
```

For a mature production environment, split that identity into a runtime user
with only `SELECT, INSERT, UPDATE, DELETE` and a deployment-only migration user
with schema privileges. Store both in the deployment secret manager.

Set Laravel:

```dotenv
DB_CONNECTION=mysql
DB_HOST=database.internal
DB_PORT=3306
DB_DATABASE=mcare
DB_USERNAME=mcare_app
DB_PASSWORD=generated-secret
MYSQL_ATTR_SSL_CA=/run/secrets/mysql-ca.pem
```

Keep strict SQL mode enabled (already configured), use TLS for a remote
database, encrypt storage/backups, take automated backups, and prove a restore
into an isolated database. Use the database-backed queue/cache/session drivers
for local or a small single instance. Move those three drivers to Redis only
when production throughput or multiple API instances justify it; clinical data
remains in MySQL.

Run forward-only production migrations:

```bash
cd backend
php artisan config:cache
php artisan migrate --force
php artisan mcare:readiness --strict --json
```

Never run `migrate:fresh`, seeders, or destructive rollback commands against
production.

## 10. Build and verify in order

Build the Flutter app with the ignored public configuration:

```powershell
Set-Location frontend
flutter pub get
flutter run -d chrome --web-port 8090 `
  --dart-define-from-file=config/app_config.staging.json
```

Then prove each integration:

1. Email verification: register with a controlled real inbox, confirm the API
   reports accepted delivery, resend once, and verify only the newest code.
2. SMS recovery: request a code on a controlled real handset and complete one
   reset; confirm invalid, expired, reused, and five-times-wrong codes fail.
3. Google Sign-In: use a real allowed Google account on web, Android, and iOS;
   verify Laravel creates/restores the correct user and rejects a wrong OAuth
   audience.
4. Maps: open a patient chart with a GPS fix; verify the embedded marker, Open
   map, and Directions on all shipped platforms.
5. Firebase registration: sign in as a verified user, allow notifications, and
   confirm one `fcm_tokens` row is refreshed for that device.
6. Background push: send an SOS test from staging, verify one generic
   lock-screen notification, tap it, and confirm authenticated canonical data
   refreshes to the correct role screen.
7. Token hygiene: disable push and sign out; confirm the device registration is
   removed. Send to an unregistered test token and confirm it is pruned.
8. Database: run the readiness audit, all migrations, application tests, an
   encrypted backup, and a restore test.
9. Browser/service worker: verify `firebase-config.json` returns 200 with
   `application/json`, the worker is active under the app scope, and only one
   notification appears per FCM message.

Real credentials, billing, provider-console registrations, release signing,
APNs upload, final domains, and physical-device delivery cannot be fabricated
by source code. Treat each successful real-device check as required release
evidence.
