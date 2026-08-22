# Quality Assurance, UAT, Performance and Rollback Plan

## Test pyramid

| Layer | Purpose |
|---|---|
| Static/analyze | Type safety, lint, route registry completeness |
| Unit | Ranking, mapping, formatting, permission unions, validation |
| Widget | Responsive composition, state variants, semantics and navigation |
| Golden | Approved visual contract by role, tier, theme and text scale |
| API contract | Request/response compatibility and error mapping |
| Backend feature | Authorization, IDOR, state transitions, audit and side effects |
| Integration/E2E | Whole journeys, realtime/poll reconciliation and rollback |
| Manual UAT | Clinical/operational clarity and safety with representative users |

## Required viewport matrix

Test at minimum: 360x800, 390x844, 599x900, 600x960, 800x1280, 1024x768, 1440x900 and 1920x1080. Repeat critical screens at 200 percent text scale and in light/dark mode.

Assertions include:

- correct bottom bar/rail form;
- no overflow or clipped critical text;
- one selected parent for every legacy child route;
- valid touch/focus target sizes;
- large lists own and virtualize scrolling;
- detail changes from sheet to drawer/pane without changing behavior;
- no unauthorized item/count/action appears.

## Route and navigation tests

- Manifest contains all 99 current constants.
- Every `main.dart` route case remains reachable with flag off.
- Every legacy route maps to one correct parent with flag on.
- Complete-profile and force-password gates remain outside hubs.
- Back/root behavior is stable from list, detail, notification and SOS entry.
- SOS/user/thread argument shapes remain compatible.
- Missing detail arguments show a safe not-found state.
- Deep-link return after login is not claimed until an allowlisted E2E test passes.

## Backend authorization matrix

For every protected route test unauthenticated, Patient, unassigned Doctor, assigned Doctor, zero-grant Assistant, exact-grant Assistant and Admin. Add cross-user/cross-patient identifiers and invalid object types.

Assert response, database side effects, notification/push creation, broadcast authorization and audit event. A denied request must not leak whether an out-of-scope object exists.

## Account/session tests

- Pending, rejected, suspended, unverified and force-password users cannot use protected APIs outside their allowed recovery flow.
- Suspension, role change, permission change and password change invalidate applicable live sessions.
- Frontend 401/419 clears role stores and PHI then navigates safely.
- Mock OAuth is impossible in production.
- Reset/invite/OTP expiry, replay, attempts and single-use are enforced.
- Endpoint limiters isolate normalized identifier and IP.

## Typed work tests

- Ranking and deduplication by stable type/id.
- Privacy-safe summaries.
- Allowed actions come from capability and object state.
- Alert acknowledgement does not resolve alert.
- Notification resolution does not resolve SOS/alert.
- Double tap sends one mutation.
- Failed request leaves item actionable with explanation.
- Version conflict reloads detail and preserves user-entered note for review.
- Clinical completion waits for server confirmation.

## Role UAT journeys

### Administrator

1. Sign in and identify the highest-priority task.
2. Filter Work and open a detail.
3. Review/complete approval with required evidence.
4. Route a care request and verify assignment.
5. Handle a support ticket.
6. Review a person and perform an authorized account action.
7. Review audit/security information.
8. Confirm rollback returns to legacy UI.

### mCare Assistant

1. Sign in with zero grants and verify only safe baseline content.
2. Repeat with each grant and verify parent/filter/action visibility.
3. Lose a grant while a detail is open and return safely.
4. Attempt a higher-role target and receive a safe denial.
5. Confirm Admin-only permissions/system are never available.

### Patient

1. Register, complete onboarding and reach Home.
2. Record normal, warning and critical vitals.
3. Log a medication dose.
4. Book/reschedule/cancel an appointment.
5. Upload/view/edit/delete a document.
6. Read/send a care-team message.
7. Request care and manage an external link.
8. Create/reply/close support.
9. Trigger/acknowledge/resolve SOS with location consent.

### Doctor

1. Identify urgent work in assigned caseload.
2. Open a patient from Work and from Patients.
3. Review monitoring, prescribe medication, schedule visit and upload document.
4. Create/edit/publish a report.
5. Resolve an alert with typed action/note.
6. Respond to SOS.
7. Lose assignment while workspace is open and close safely.

### External clinician

1. Resolve valid link/code.
2. Confirm one-patient scope and expiry.
3. Review permitted summary sections.
4. Submit each permitted finding and receive a durable receipt.
5. Verify an unpermitted action is absent and server-denied.
6. Exercise invalid, expired, revoked, throttled, offline and End session states.

## Accessibility QA

- Keyboard-only path for every web action.
- Focus order follows visual order; dialogs/sheets trap and restore focus.
- Screen-reader labels include name, role, value and state.
- Status not conveyed by color alone.
- 200 percent text without loss of content/function.
- Reduced motion respected.
- Contrast meets WCAG 2.2 AA.
- Charts have text equivalents.
- Error summary is announced and field errors are associated.

## Performance budgets

- No eager rendering of large Work/People/Patient lists.
- Home adapters compute once per state revision and avoid duplicate scans.
- No duplicated network request caused by each responsive child.
- Poll refresh does not rebuild the entire shell unnecessarily.
- Images/docs load on deliberate open, not dashboard hydration.
- Expanded screens use max content width and avoid expensive global blur.

Record cold screen render, list scrolling, route transition, session hydration and action acknowledgment on representative low/mid devices and browsers. Establish numeric budgets from Phase 0 baseline before cutover.

## Privacy and security QA

- Inspect push payloads, URLs, browser history/cache, analytics events and logs for PHI.
- Verify private document delivery and signed/authorized expiration.
- Verify external raw secrets are absent after exchange.
- Verify clipboard/share behavior warns about sensitive links.
- Verify account switch/logout clears all role and external-session state.
- Verify permission-revoked buckets are not rendered from stale stores.

## Release and rollback rehearsal

1. Deploy code with all new flags false.
2. Run legacy smoke suite.
3. Enable one internal role cohort.
4. Run role UAT and error monitoring.
5. Flip flag false during an active session and confirm safe return.
6. Confirm no migration/API downgrade is required.
7. Re-enable only after root cause and regression test.

## Release evidence pack

- Test results and coverage summary.
- Golden diff approval.
- Accessibility report.
- Security/IDOR matrix.
- API contract report.
- Performance comparison.
- UAT signatures.
- Feature-flag and rollback proof.
- Known limitations and future-backend exclusions.

