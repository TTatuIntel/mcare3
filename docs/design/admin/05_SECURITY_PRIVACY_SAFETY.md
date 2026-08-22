# 05 — Security, Privacy and Clinical Safety Blueprint

## 1. Status and scope

This is a pre-implementation security design, not a certification. It records code-observed controls, known risks, target controls, and test gates for the Guided Operations Hub and the wider platform surfaces it depends on.

**Cutover rule:** The Guided Operations Hub must not be enabled for production users until all P0 items below are fixed or formally risk-accepted by the accountable security/product owner with compensating controls and expiry.

## 2. Security principles

1. **Server authoritative:** Flutter visibility is never authorization.
2. **Default deny:** Unknown role, capability, object type, command, or state transition fails closed.
3. **Minimum necessary:** Do not preload or display PHI that is not required for the current task.
4. **Object scope:** Every supplied ID is untrusted and checked against role, scope, object type, and actor-target relationship.
5. **Typed commands:** SOS, alerts, notifications, support, and security incidents never share a generic Resolve implementation.
6. **Least privilege:** Capability, target hierarchy, team/scope, reason, expiry, and recent authentication all matter.
7. **Immediate revocation:** Suspension, role/permission change, reset, rejection, or security event invalidates affected sessions.
8. **Auditability:** Sensitive reads, exports, downloads, and writes produce an appropriate audit record without duplicating unnecessary PHI.
9. **Safe failure:** 401 clears state, 403 removes restricted data, network failure shows stale/offline state, and conflict never silently overwrites.
10. **One secure product:** Web and native use platform-appropriate session storage behind one interface.

## 3. Threat boundaries

1. Public registration, login, recovery, OTP, invites, Google/Apple OAuth
2. Authenticated patient self-scope
3. Doctor active-caseload scope
4. Administrator versus delegated assistant
5. External-doctor guest capability
6. Realtime polling, FCM, notifications, lock screens and third parties
7. Upload, scanning, storage and download/stream delivery
8. Browser storage, native device storage, offline/cache and crash telemetry
9. Database, audit, exports, operational access and backups

## 4. Existing controls to preserve

- Authenticated API groups use Sanctum, general throttling, and role middleware.
- Assistant permissions are stored server-side and checked per request by `EnsurePermission`; admin bypass is explicit.
- Permission and System endpoints have additional admin-only role gates.
- Login, external code exchange, external writes, and general APIs have named rate limits.
- Many patient/doctor resources apply owner/caseload checks.
- External links have randomized secrets, expiry, active-link limits, revoke, and create/revoke audit.
- Many admin mutations use centralized `AuditService`.
- Password reset by admin revokes the target user's tokens.
- Assistant grants refresh during the poll cycle and protected requests re-check the database.
- Exact production/local CORS origins are listed instead of wildcard origins.
- File endpoints perform some extension/MIME/size validation.

These controls are useful but do not close the blockers below.

## 5. P0 production and cutover blockers

| ID | Risk observed | Required outcome |
|---|---|---|
| SEC-P0-01 | Mock Google/Apple OAuth paths accept caller-influenced identities without a production environment guard | Compile/runtime disable outside local/testing; production boot fails if mock OAuth is enabled; automated negative test |
| SEC-P0-02 | Protected API access does not consistently enforce active, approved, verified, and completed forced-password account state | Central account-state middleware; temp-password token limited to required password flow; invite/approval sequence corrected |
| SEC-P0-03 | Suspension/role/grant changes do not uniformly revoke or invalidate existing indefinite Sanctum tokens | Finite expiry/rotation plus `auth_version` or equivalent; revoke/bump on suspension, rejection, role/grant/reset changes |
| SEC-P0-04 | Coarse assistant people permissions permit sensitive actions against broad targets, including potentially higher roles | Split capabilities; target-hierarchy policy; preserve final active admin; no assistant equal/higher privilege mutation |
| SEC-P0-05 | Zero-grant assistants currently receive broad alert/support/message and some SOS-related PHI | Explicit view/action abilities; redacted count-only summary; fetch detail only after authorization |
| SEC-P0-06 | SOS push/notification/broadcast recipient logic can include assistants without emergency-location permission | Capability-filter recipients and channels; generic lock-screen text; no location/patient note in push payload |
| SEC-P0-07 | Global vital thresholds can be changed too broadly and partial updates need invariant validation | Governed clinical capability, domain invariants, version/reason/audit, rollback, recent MFA; consider dual approval |
| SEC-P0-08 | Web bearer token is stored in localStorage and token expiration is null; API lacks centralized auth-failure cleanup | Web HttpOnly Secure SameSite session/CSRF design; native secure storage; global 401/419 handler; finite sessions |
| SEC-P0-09 | External guest links are powerful, secrets are returned/stored too openly, and access/read auditing/verification is limited | Hash secrets, show once, short-lived portal session, scoped default-deny actions, strip token from URL, audit every access/write |
| SEC-P0-10 | Medical/credential files use public-disk patterns despite authenticated streams | Private encrypted storage, authorized delivery, no-store/nosniff, AV/quarantine/CDR, real MIME, EXIF stripping, download audit |
| SEC-P0-11 | Some bound objects lack strong type/actor-target checks; notification ownership and assignment roles need policies | Scoped queries/policies, 404 out-of-scope, role/type validation, negative IDOR matrix |
| SEC-P0-12 | Reset/invite/OTP flows need expiry, hashing, atomic single use, replay protection and session revocation | Expiring hashed secrets, attempt counters, atomic consume, session invalidation and tests |
| SEC-P0-13 | Auth limiter's secondary key reads `email` while some endpoints submit `identifier`, risking cross-user/global throttling | Endpoint-specific normalized identifier+IP limiters; independent auth/recovery budgets |
| SEC-P0-14 | Unified queue could map different aggregates to an unsafe generic resolve action | Typed server commands, `allowed_actions`, idempotency, state version, confirmation/reason; canonical endpoint tests |

## 6. Authentication and session architecture

### Current state

- Flutter uses a bearer token in `ApiClient`.
- Web persistence stores token and user snapshot in localStorage.
- CORS currently has `supports_credentials=false`.
- Sanctum token expiration is currently null.
- Session services can swallow auth/network errors, leaving stale state visible.

### Target shared interface

```text
AuthRepository
├── WebSessionAdapter      -> HttpOnly Secure SameSite cookie + CSRF
└── NativeSessionAdapter   -> Keychain/Keystore secure storage + rotated token
```

The rest of Flutter depends only on `AuthRepository`, not platform token details.

### Web

- Use first-party Sanctum SPA session cookies where deployment topology permits.
- Enable exact stateful domains and credentials.
- Fetch CSRF cookie and send required anti-CSRF header for state-changing requests.
- Cookies: Secure, HttpOnly, appropriate SameSite, scoped Domain/Path, finite lifetime.
- Verify Origin/Referer for cookie-authenticated writes.
- Strict CSP, `frame-ancestors`, `nosniff`, Referrer-Policy, Permissions-Policy, and no-store for sensitive responses.
- No analytics/session-replay scripts in the external portal or clinical detail.

If bearer auth remains temporarily, use short-lived in-memory access tokens and a protected rotation design; localStorage is not accepted for the production health-data target.

### Native

- Store session secret only in Keychain/Keystore via a platform adapter.
- Use short-lived, rotated, revocable tokens with server-side device/session metadata.
- Clear secure storage and every role/PHI store on logout, 401, or revocation.
- Optional device binding/biometric unlock must not replace server session validation.

### Account-state middleware

Every protected route and realtime/broadcast authorization enforces:

- active status;
- correct approval state;
- email/identity verification as required;
- forced password completed, except the narrowly allowed password endpoint;
- token/session version current;
- role/capability current.

## 7. Capability and target model

Replace coarse permissions incrementally with explicit abilities, for example:

- `people.directory.view`
- `patient.clinical.view`
- `alerts.view`, `alerts.acknowledge`, `alerts.resolve`
- `support.assigned.view`, `support.all.view`, `support.reply`, `support.assign`
- `messages.direct`, `messages.oversight`
- `users.create`, `users.status`, `users.reset`
- `roles.manage_nonprivileged`
- `privileged_roles.manage` — admin-only
- `sos.metadata`, `sos.location`, `sos.respond`
- `audit.view`, `audit.export`
- `vital_catalog.view`, `vital_catalog.manage`

`/auth/me` returns canonical capabilities and `capability_version`. During migration, one compatibility mapper translates existing 12 keys. UI and PHP constants should be generated/shared or contract-tested to prevent drift.

Capabilities can later carry team/patient scope, reason, expiry and `revoked_at`.

### Target hierarchy

- Assistant cannot change/reset/suspend/promote an admin.
- Assistant cannot act on equal/higher privileged staff unless an explicit narrowly scoped policy permits it.
- Self-demotion/suspension and last-active-admin removal are blocked.
- Privileged role promotion and permission management require admin, recent MFA, reason, and strong confirmation.

## 8. Sensitive action tiers

| Tier | Examples | Required interaction |
|---|---|---|
| 1 | Mark notification read, open authorized detail | Normal authenticated action |
| 2 | Acknowledge alert, reply support, routine assignment | Confirmation where consequence is meaningful; idempotency |
| 3 | Resolve clinical alert, SOS response/location, approve credential, remove care assignment | Recent re-auth, reason/note, conflict check, audit |
| 4 | Password reset, permission/admin-role change, audit export, system/threshold change | MFA/step-up, explicit target/impact, reason, strong confirmation; consider dual control |

Do not return plaintext temporary passwords to staff. Use expiring reset/invite links delivered through a verified channel.

## 9. Work queue safety

- Work items include typed `allowed_actions` from server.
- UI adapters delegate to canonical endpoints.
- Commands include idempotency key and state version.
- Server state machine rejects invalid/repeated transitions.
- Clinical items are not optimistically marked complete.
- SOS notification and SOS event have separate identities; the canonical SOS event controls emergency resolution.
- A stale item returns 409/appropriate conflict response and refreshes context.
- Permission change cancels pending detail operations and purges restricted item data.

## 10. PHI and privacy

### Home and summary

- Return counts and 3–5 redacted task summaries.
- Do not preload 100 users, 200 alerts, and full ticket content every poll for the new hub.
- Fetch clinical/ticket/credential detail only on deliberate authorized open.
- Do not show unnecessary readings in platform activity.

### Directory

- Display identity, role/status, and minimal operational context only.
- Clinical summary is absent until authorized patient detail is opened.

### Prohibited PHI locations

- Push/lock-screen payload
- URL path/query/fragment
- analytics/session replay
- crash/error logs
- browser cache/service-worker cache
- generic recent-activity feed
- clipboard by default
- filenames and export names where avoidable

### Privacy/shield mode

Consider a staff privacy mode that masks names/identifiers until interaction for shared environments. Screen capture prevention can be applied on supported native platforms for the most sensitive detail, with accessibility and operational trade-offs documented.

## 11. SOS, notifications and realtime

- Recipient queries filter active status, capability, and scoped responsibility.
- Push copy: `Urgent mCare task — sign in to view` rather than patient name, note, or location.
- Broadcast/channel authorization applies the same checks.
- Notification payload carries opaque task reference, not PHI.
- Poll and push reconcile canonical server state; neither grants access.
- Location opens only after current capability and object authorization.
- Logs never contain coordinates or emergency note unless a restricted audit requirement explicitly demands it.

## 12. External doctor access

- Store token/code hashes; never persist raw recoverable secrets.
- Show patient-created secret once.
- Exchange link/code for a short-lived portal session and remove the token from URL/history.
- Patient selects scopes and duration; default scope is view-only.
- Medication/clinical writes require explicit scope and verified clinician/step-up policy.
- Audit resolve, summary view, document access, and every write using portal session/token ID, never raw secret.
- Patient can review access history and revoke immediately.
- Rate limits are distributed and scoped by token/session plus abuse signals.
- `Cache-Control: no-store`, strict Referrer-Policy, CSP and no third-party replay/analytics.

## 13. Files and downloads

- Store medical documents and credentials on private encrypted local/S3 storage.
- Do not depend on `storage:link` for protected PHI delivery.
- Authorize every read/stream/download against current role/object scope.
- Validate content by magic bytes and parser, not only name/client MIME.
- Quarantine and scan; use CDR/re-encode where appropriate.
- Strip EXIF from images.
- Reject or safely attachment-serve risky legacy formats.
- Prevent zip bombs/polyglots and set strict size/page limits.
- Responses use no-store, nosniff, safe disposition, and bounded filename.
- Audit sensitive download/export.

## 14. Audit design

Append-only event fields:

- actor ID and effective role/capabilities
- action and object type/ID
- subject ID when needed
- authorization decision/outcome
- reason
- correlation/request ID
- UTC timestamp
- IP/user agent/device/session context
- policy/capability version
- before/after field names or safe values, avoiding unnecessary PHI duplication

Audit login success/failure/lockout, permission denial, PHI read/download/export, external access, privileged changes, and security control changes. Critical write + audit must be transactional or use an outbox. Exporting the audit is itself audited. CSV export neutralizes cells beginning with `=`, `+`, `-`, or `@`.

## 15. HTTP and deployment controls

- HTTPS only; HSTS after verified rollout.
- Exact CORS origins; credentials only for intended first-party web origin.
- Secure cookies and origin checks if web cookie auth is adopted.
- CSP with no unsafe third-party clinical-page scripts.
- `X-Content-Type-Options: nosniff`.
- `Content-Security-Policy: frame-ancestors 'none'` or controlled equivalent.
- Strict Referrer-Policy, especially external portal.
- No-store for authenticated PHI/API responses where appropriate.
- Secrets in managed secret storage; production debug disabled.
- Encrypted backups with tested restoration and access logging.

## 16. Required security tests

### RBAC and IDOR matrix

For every route/resource:

- unauthenticated
- patient
- unassigned doctor
- assigned doctor
- zero-grant assistant
- exact-grant assistant
- admin
- cross-patient/cross-target IDs

Assert response, returned fields, and DB side effects.

### Session/account

- Pending, rejected, suspended, unverified, and must-change users cannot call protected APIs.
- Suspension, role/grant change, password reset, and rejection invalidate active sessions.
- 401 wipes frontend PHI state.
- Mock OAuth is impossible in production.
- Reset/invite/OTP expiry, replay and brute force are covered.

### Privacy channels

- Unauthorized assistants receive no SOS/alert/support PHI in session, notification, FCM or broadcast.
- Search terms/PHI do not appear in URL/logs/telemetry/cache.
- External scope and revoke races are tested.

### File and clinical governance

- Spoofed MIME, malware test artifact, polyglot, zip bomb, unauthorized stream and signed-link expiry.
- Vital threshold invariants/property tests, step-up, reason/audit, rollback.

### Audit/concurrency

- Audit completeness and authorization.
- Audit failure handling for critical writes.
- CSV injection neutralization.
- Idempotency and stale-version conflicts for each task command.

## 17. Security release gate

Production enablement requires:

- all SEC-P0 items closed or time-bounded formal exception;
- RBAC/IDOR matrix green;
- no PHI in push, URL, cache or telemetry checks;
- auth/session rotation and revocation tests green;
- private file path and scan/delivery tests green;
- typed Work command contract tests green;
- dependency and static security scans reviewed;
- production-like migration and rollback rehearsal complete.

