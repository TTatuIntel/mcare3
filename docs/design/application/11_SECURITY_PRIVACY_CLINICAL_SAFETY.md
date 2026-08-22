# Security, Privacy and Clinical Safety Blueprint

## Security design rule

Laravel is authoritative. Flutter navigation, hidden buttons and permission gates improve usability but never grant access. Every identifier is untrusted, every object query is scoped, and every response contains the minimum necessary data for the current decision.

## Threat boundaries

1. Public authentication, OAuth and account recovery.
2. Authenticated patient self-scope.
3. Doctor active-caseload scope.
4. Administrator versus delegated Assistant authority.
5. External token/code guest capability.
6. Push, realtime and third-party delivery.
7. Medical-file storage, scanning and authorized delivery.
8. Browser/native session and local cache.
9. Database, audit, backup and production operations.

## P0 findings before production visual cutover

| Risk | Required gate |
|---|---|
| Production mock OAuth paths can accept caller-controlled mock identities | Restrict to local/testing and fail production boot if enabled |
| Account state is not uniformly enforced after token issue | Server middleware for active, approved, verified and password-complete state |
| Suspension/role/grant changes do not uniformly invalidate long-lived tokens | Auth version/session revocation on status, role, password and privilege change |
| Coarse Assistant people grants can affect broad/high-privilege targets | Split abilities, enforce actor-target hierarchy, protect last active admin |
| Baseline Assistant feeds can expose alert/support/message/SOS PHI | Explicit view/action capabilities and redacted/count-only summaries |
| SOS push/broadcast can reach Assistants without location grant | Filter every recipient/channel and use generic lock-screen copy |
| Global vital catalog is too broadly mutable | Governed clinical ability, invariants, versioning, reason and step-up |
| Web bearer session is exposed to localStorage/XSS and lacks central auth-failure cleanup | HttpOnly cookie/CSRF target for web, secure native storage, finite sessions, global 401 cleanup |
| External guest secrets and abilities are too broad | Hashed secrets, short portal session, explicit scopes, read/write audit, view-only default |
| Medical files use public-disk patterns | Private encrypted storage, authorized stream/signed delivery, scanning and no-store headers |
| Object-type/target hierarchy gaps exist in selected admin operations | Policies/scoped queries and negative IDOR tests |
| Reset/invite/OTP expiry and single-use controls are incomplete | Hash secrets, enforce expiry/attempts, atomic consume, revoke sessions |
| Login limiter mixes `email` and `identifier` keys | Endpoint-specific normalized identifier plus IP limiters |
| Generic queue completion can update the wrong aggregate | Typed commands, state machines, idempotency and optimistic version checks |

The full security remediation is a prerequisite to enabling the redesigned experience, not a visual-design enhancement.

## Session architecture target

### Web

Use an HttpOnly, Secure, SameSite cookie with the Sanctum CSRF flow, exact stateful domains, credentialed CORS and origin checking. Add a strict CSP, `frame-ancestors`, `nosniff`, Referrer-Policy and Permissions-Policy.

### Native

Use platform Keychain/Keystore-backed storage through one session adapter. Do not duplicate authentication repositories by platform.

### All platforms

- finite expiry and refresh/rotation policy;
- server-side auth/capability version;
- centralized 401/419 handling;
- immediate clearing of role stores and PHI on invalidation;
- a safe reauthentication path for sensitive actions;
- no silent success when session refresh fails.

## Authorization target

Move from coarse role/permission checks toward explicit capabilities such as:

- `people.directory.view`;
- `patient.clinical.view`;
- `alerts.view`, `alerts.ack`, `alerts.resolve`;
- `support.assigned.view`, `support.all.view`, `support.reply`, `support.assign`;
- `users.create`, `users.status`, `users.reset`;
- `roles.manage_nonprivileged`, `privileged_roles.manage`;
- `sos.metadata`, `sos.location`, `sos.respond`;
- `audit.view`, `audit.export`;
- `vital_catalog.view`, `vital_catalog.manage`.

Capabilities may include team scope, expiry, reason and revocation time. `/auth/me` returns canonical capabilities plus a version. Each task detail returns allowed actions. Server denial remains decisive.

## Sensitive-action tiers

| Tier | Examples | Requirement |
|---|---|---|
| Standard | Read authorized list, filter, navigate | Active session and role/object scope |
| Confirmed | Close support, cancel care request, delete draft | Explicit confirmation and durable receipt |
| Clinical | Resolve alert, change care assignment, respond SOS, credential approval | Recent re-auth where appropriate, reason, typed command, audit |
| Privileged | Password reset, role/permission change, audit export, system/threshold change | MFA/step-up, strong confirmation, audit; dual control where policy requires |

## Minimum-necessary dashboard policy

Home and notification summaries show counts and redacted descriptions. Full patient name, vital value, note, location or ticket body appears only after authorized deliberate open. No PHI belongs in URLs, push text, crash logs, analytics properties, browser caches or session-replay products.

## Push and realtime

- Recipient selection repeats capability and account-state checks.
- Lock-screen text is generic: “Urgent mCare task - sign in to view.”
- Broadcast authorization mirrors REST policy.
- Permission revocation removes a live detail immediately.
- Notification resolution never implies underlying clinical resolution.
- Polling remains a reconciliation safety net during realtime rollout.

## External Clinical Access hardening

Before the new external workspace is enabled:

1. Store token and code hashes; reveal the secret once.
2. Exchange link/code for a short-lived portal session and remove the raw token from URL/history.
3. Add explicit `summary.read`, `vitals.create`, `notes.create`, `medications.create`, `documents.create` scopes.
4. Default to view-only; require explicit policy for medication and upload.
5. Audit resolve, view, document access and every write without storing raw secrets.
6. Recheck expiry/revocation and scope atomically at write time.
7. Use no-store, no-referrer and a portal-specific CSP with no third-party replay.
8. Add idempotency for writes and clear external session state only on End session.
9. Confirm patient identity, allergies and scope before medication assignment.
10. Never expose another patient through navigation, search or error detail.

## File security

- Store medical files outside public web roots or in encrypted private object storage.
- Verify actual MIME and extension; reject spoofing and risky legacy formats.
- Quarantine and scan uploads; consider content disarm/reconstruction.
- Recompress images and strip EXIF where clinically safe.
- Deliver through authorized streaming or short signed URLs.
- Set `no-store` and `nosniff`; force attachment for risky document types.
- Audit read, download, upload, replace and delete.
- Sanitize filenames and descriptions; prevent CSV/formula injection in exports.

## Audit target

An append-only event records actor/effective role, action, object, subject, authorization decision, outcome, reason, correlation ID, UTC time, IP/device context and policy version. Before/after field names may be recorded without duplicating sensitive values.

Audit authentication events, permission denials, PHI reads/downloads/exports, external access, sensitive writes and audit export itself. Couple critical mutation and audit through one transaction or outbox, then ship to a tamper-evident retention target.

## Clinical safety interaction rules

- Critical, warning and normal use universal semantics.
- Threshold and unit appear beside clinical values.
- Acknowledgement and resolution are distinct.
- Resolution requires the action taken and appropriate note/reason.
- SOS uses its own state machine and endpoint.
- Clinical completion waits for server success.
- Conflicts return the latest state for review; the UI does not overwrite silently.
- Offline mode permits safe read-only last-known information unless an explicitly designed offline write queue exists.
- The application never claims diagnosis or emergency-service replacement.

## Privacy toggles and consent truth

Patient privacy preferences currently persist, but repository evidence does not show every toggle enforcing backend authorization. The design must not describe a preference as a security boundary until enforcement tests prove it. External access creation/revocation remains the actual token-control workflow.

## Security release evidence

- Complete role/capability/IDOR route matrix.
- Active session invalidated after suspension, role, password or privilege change.
- Zero-grant Assistant receives no restricted rows, counts, pushes or broadcasts.
- External scope/expiry/revoke race and audit tests.
- Upload polyglot, malware, zip-bomb, size and unauthorized-stream tests.
- No PHI in push, URL, analytics, logs or cache inspection.
- Clinical state-machine, duplicate-submit and conflict tests.
- Audit atomicity, tamper and export authorization tests.

