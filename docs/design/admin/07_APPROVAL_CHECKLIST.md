# 07 — Approval and Release Checklist

## A. Product/UX approval

- [ ] Four persistent destinations approved: Home, Work, People, More
- [ ] Messages approved as a Work filter/secondary entry rather than a fifth tab
- [ ] Goal labels approved: Urgent care, People, Requests, Platform
- [ ] Home maximum of three compact next actions approved
- [ ] Work ranking order approved by clinical/operations owner
- [ ] Minimum-necessary patient summary approved
- [ ] Mockups accepted as direction, with specifications authoritative over generated-image artifacts

## B. Architecture approval

- [ ] One shared Admin/Assistant implementation approved
- [ ] Existing named routes retained
- [ ] Navigator 1 retained for this redesign
- [ ] Current 600/1024/1440 breakpoints retained
- [ ] Compact bottom bar, medium compact rail, expanded rail approved
- [ ] Shared Work model/composer/controller approved
- [ ] No global patient/doctor theme rewrite in first phase

## C. Backend/contract approval

- [ ] Existing endpoint traceability reviewed
- [ ] Additive capability/session fields approved
- [ ] Unauthorized fields absent/null rather than zero approved
- [ ] Redacted work-summary contract approved
- [ ] Typed `allowed_actions` and state version approved
- [ ] Existing session contract retained for old clients during compatibility window

## D. Security approval

- [ ] SEC-P0-01 through SEC-P0-14 assigned, fixed, or formally excepted
- [ ] Mock OAuth impossible in production
- [ ] Account-state middleware and immediate revocation verified
- [ ] Web/native session storage architecture approved
- [ ] Assistant capability and target hierarchy approved
- [ ] SOS push/broadcast/location privacy verified
- [ ] External access scope/session/audit plan approved
- [ ] Private file storage/scanning/delivery verified
- [ ] RBAC/IDOR matrix green
- [ ] No PHI in push, URL, telemetry, cache or generic activity

## E. Accessibility approval

- [ ] WCAG AA contrast verified
- [ ] Status uses icon + label + colour
- [ ] 48 px compact/medium touch targets verified
- [ ] Keyboard activation, focus order and Escape behavior verified
- [ ] Screen-reader semantics reviewed
- [ ] 200% text has no clipped primary labels/actions
- [ ] Reduced-motion and dark-mode behavior verified

## F. Implementation gates

- [ ] Phase 0 baseline recorded
- [ ] Route registry exhaustive tests green
- [ ] Feature flags default off
- [ ] Admin and Assistant flags are independent
- [ ] Flag-off legacy route behavior green
- [ ] Flag-on compatibility behavior green
- [ ] Atomic session snapshot/stale state behavior green
- [ ] Work dedupe/ranking/redaction tests green
- [ ] Typed mutation/error/conflict tests green
- [ ] Flutter analyze/tests green
- [ ] Backend tests green

## G. Rollout approval

- [ ] Staging rehearsal complete
- [ ] Internal admin cohort successful
- [ ] Partial-grant Assistant matrix successful
- [ ] Mobile, tablet, web and Windows verification complete
- [ ] Telemetry dashboards/alerts active without PHI
- [ ] Server-side rollback flag rehearsed
- [ ] Legacy screens retained for at least one complete mobile release after 100%

## Decision record

| Decision | Owner | Date | Outcome/notes |
|---|---|---|---|
| Product design |  |  |  |
| Clinical safety |  |  |  |
| Security/privacy |  |  |  |
| Backend/API |  |  |  |
| Flutter architecture |  |  |  |
| Accessibility |  |  |  |
| Production rollout |  |  |  |

