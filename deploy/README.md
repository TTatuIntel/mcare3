# mCare production operations

These files are deployment templates. Replace every `example.com`, filesystem
path, service account, and certificate reference for the target environment.
Never place production secrets in this repository.

## Deployment sequence

1. Provision Linux, PHP 8.2+, PHP-FPM, Nginx, MySQL/MariaDB, Redis, Node/build
   tooling, TLS certificates, and an unprivileged `www-data` runtime user.
2. Install backend dependencies with `composer install --no-dev --optimize-autoloader`.
3. Configure `backend/.env`, then run `php artisan mcare:readiness --strict`.
4. Run `php artisan migrate --force`, `php artisan storage:link`,
   `php artisan config:cache`, `php artisan route:cache`, and
   `php artisan event:cache`.
5. Build Flutter web with the production API, WSS, Google, Apple, and Firebase
   dart-defines. Copy `web/firebase-config.example.json` to
   `web/firebase-config.json` before the build and fill in the same public
   Firebase project values.
6. Install the Nginx and systemd templates, run `nginx -t`, then enable and
   start `mcare-queue`, `mcare-reverb`, and `mcare-scheduler`.
7. Confirm `/up`, `/ready`, an authenticated session read, a private Reverb
   subscription, one push per platform, email delivery, and object upload.

Recommended production frontend values include:

```text
MCARE_API_URL=https://api.example.com/api/v1
MCARE_WS_URL=wss://api.example.com
MCARE_WS_APP_KEY=<same as REVERB_APP_KEY>
MCARE_GOOGLE_CLIENT_ID=<web OAuth client>
MCARE_GOOGLE_SERVER_CLIENT_ID=<web OAuth client>
MCARE_GOOGLE_IOS_CLIENT_ID=<iOS OAuth client>
MCARE_APPLE_CLIENT_ID=<Apple Services ID>
MCARE_APPLE_REDIRECT_URI=https://app.example.com/
MCARE_FIREBASE_*=<Firebase public app settings>
```

## Runtime supervision and monitoring

Monitor the following independently; alert only after a short sustained
failure to avoid noisy transient alerts:

- HTTPS `GET /up`: PHP/application process liveness.
- HTTPS `GET /ready`: database, storage, and non-ephemeral cache readiness.
- `systemctl is-active mcare-queue mcare-reverb mcare-scheduler`.
- Queue age, `failed_jobs` count, HTTP 5xx rate, p95/p99 latency, database
  saturation, Redis memory, disk space, TLS expiry, and backup age.
- A synthetic authenticated read and a private WSS subscribe from outside the
  network. Do not put patient data in monitor labels or logs.

The WebSocket server binds only to loopback. Nginx terminates TLS and proxies
`/app` and `/apps`, so the public client always uses WSS. Reverb, the queue,
and the scheduler restart automatically under systemd.

## Load verification

Install k6 on the test runner and target a staging environment:

```bash
k6 run -e BASE_URL=https://api.staging.example.com deploy/load/k6-smoke.js
k6 run -e BASE_URL=https://api.staging.example.com \
  -e AUTH_TOKEN='<patient token>' -e SESSION_PATH=/api/v1/patient/session \
  -e RATE=25 -e DURATION=5m deploy/load/k6-smoke.js
```

Use synthetic accounts only. Increase load gradually, watch database/Redis
metrics, and stop when the agreed error or latency budget is exceeded.

## Backup and recovery

Automate encrypted, off-host backups for both the database and durable object
storage. The database job should use a restricted credentials file (not a
password on the command line), a transaction-consistent dump, compression,
encryption, checksums, retention, and an alert on failure. Enable object
versioning and lifecycle retention on the production bucket.

At least quarterly, restore the database and object files into an isolated
environment, run migrations, execute `php artisan mcare:readiness --strict`,
and verify sampled document checksums and an authenticated clinical workflow.
Record restore time and data-loss window against the approved RTO/RPO. A
backup is not release evidence until a restore has passed.

## Release evidence and rollback

Before approval, archive the commit SHA, dependency lockfiles, successful
backend/frontend test reports, k6 result, platform push/email/upload results,
signed mobile artifact hashes, accessibility/UAT sign-off, recovery-test
record, privacy/security approval, and monitoring screenshots.

For rollback, retain the previous frontend bundle and application release.
Prefer forward-compatible migrations. If a migration is not reversible,
document and rehearse its restore procedure before deployment. Stop workers,
restore the prior release, clear/rebuild Laravel caches, restart services, and
verify `/ready` plus the critical synthetic workflow.
