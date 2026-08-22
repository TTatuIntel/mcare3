# Stakeholder Approval Checklist and Future-Backend Backlog

## Design approval checklist

- [ ] The target navigation for every role is understood and approved.
- [ ] Admin and Assistant use the same implementation with permission-filtered content.
- [ ] mCare Assistant is understood as delegated human staff, not AI.
- [ ] Patient SOS remains globally reachable.
- [ ] Doctor content is limited to active caseload and authorized conversations.
- [ ] External access is understood as one patient, one expiring guest session.
- [ ] Role accent colors do not replace clinical status colors.
- [ ] Mobile, tablet, desktop and wide layouts are approved.
- [ ] Light/dark and accessibility requirements are approved.
- [ ] High-fidelity images are accepted as visual direction; written contracts are authoritative.

## Functional approval checklist

- [ ] All current routes remain available during migration.
- [ ] Existing API clients and state stores remain canonical.
- [ ] Existing mutations remain in legacy details until migrated and tested.
- [ ] Typed actions preserve acknowledgement/resolution/SOS semantics.
- [ ] Missing modules are not added as empty navigation items.
- [ ] Feature flags are role-specific and default false.
- [ ] Immediate rollback to legacy UI is accepted.

## Security gate checklist

- [ ] Mock OAuth production bypass closed.
- [ ] Account-state middleware and token invalidation complete.
- [ ] Assistant baseline PHI and target hierarchy corrected.
- [ ] SOS push/broadcast recipients capability-filtered.
- [ ] Web/native session storage and global auth-failure handling approved.
- [ ] External token/session/scope/audit hardening complete before external v2.
- [ ] Medical documents use private, scanned, authorized delivery.
- [ ] RBAC/IDOR and audit matrices pass.
- [ ] No PHI in push, URLs, analytics, logs or unintended cache.

## Administrator pilot approval

- [ ] Phase 0 route/API/response baseline complete.
- [ ] Design System v2 components are additive.
- [ ] Home shows truthful freshness and privacy-safe summaries.
- [ ] Work first links to existing details.
- [ ] People target hierarchy is enforced server-side.
- [ ] More contains only currently backed tools.
- [ ] Internal cohort UAT and rollback rehearsal pass.

## Role-by-role sign-off

| Role | Product owner | Clinical/security owner | Engineering owner | Status/date |
|---|---|---|---|---|
| Administrator |  |  |  |  |
| mCare Assistant |  |  |  |  |
| Patient |  |  |  |  |
| Doctor |  |  |  |  |
| External Clinical Access |  |  |  |  |

## Future-backend backlog

The following concepts are intentionally outside the current presentation-only implementation. Each requires discovery, data model, API, authorization, audit, privacy, operational and test design before high-fidelity screens become an implementation contract.

| Future product | Required foundation |
|---|---|
| Structured laboratory | Order, specimen, analyte, reference range, result, abnormal flag, amendment and provider workflows |
| Imaging/radiology | Order, study metadata, report, image/PACS access, amendment and secure viewer policy |
| Billing/payments | Charge, invoice, ledger, refund, gateway/webhook, reconciliation, receipt and financial audit |
| Insurance | Payer, policy, eligibility, authorization, claim, denial and privacy policy |
| Pharmacy | Medication catalog, stock, dispense, substitution, controlled-drug policy and reconciliation |
| Referral | Referral reason, recipient, consent, record package, status and closed-loop response |
| Integrated video | Provider, waiting room, consent, device/media permissions, recording policy and failure fallback |
| AI care guide | Intended use, non-diagnostic boundaries, model/provider, consent, data minimization, evaluation and human escalation |
| Clinical decision support | Evidence/version governance, explainability, alert fatigue, override reason and clinical safety case |
| Backup/recovery UI | Privileged operations boundary, encryption, restore drills, dual control and immutable audit |
| Integrations/API keys | Secret vault, scoped credentials, rotation, webhook signing, environment separation and audit |
| Authenticated external-doctor portal | Identity proofing, organizations, RBAC, consent, patient assignment, messaging and session governance |

## Decision log template

| Decision | Choice | Reason | Owner | Date |
|---|---|---|---|---|
| Navigation labels |  |  |  |  |
| Admin pilot cohort |  |  |  |  |
| Patient four-hub migration |  |  |  |  |
| Doctor workspace grouping |  |  |  |  |
| External write scopes |  |  |  |  |
| Dark-mode release scope |  |  |  |  |

## Final approval statement

Approval means stakeholders accept the information architecture, shared visual system, screen families, current-versus-future boundaries and safe phased implementation approach in this blueprint. Production enablement remains conditional on the technical, security, clinical-safety, accessibility and UAT release gates.

