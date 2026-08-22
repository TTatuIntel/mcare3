# Executive Vision, Document Control and Product Truth

## Document purpose

This is the approval baseline for the complete mCare presentation layer. It defines how the Administrator, delegated mCare Assistant, Patient, Doctor and External Clinical Access experiences should look and behave before production UI migration begins.

The design changes navigation, hierarchy, layout and component presentation. It does not silently replace Laravel policies, REST contracts, state stores, clinical thresholds, notifications, SOS workflows, reports, storage behavior or database rules.

> Approval of a visual concept is not approval to bypass a missing backend capability. Every screen is classified against the current repository before it can enter implementation.

## Document control

| Field | Value |
|---|---|
| Product | mCare Remote Patient Monitoring Platform |
| Blueprint | Complete UI/UX Design System and Safe Implementation Blueprint |
| Version | 3.0 - stakeholder approval draft |
| Repository audit date | 2026-08-07 |
| Runtime implementation status | Not cut over; legacy UI remains authoritative |
| First implementation pilot | Administrator, behind an independent runtime feature flag |
| Platforms | Flutter mobile, tablet, web and Windows from one codebase |
| Backend | Laravel 12 REST API and current MySQL schema |
| Classification | Private - product, security and engineering design |

## What this blueprint approves

- One design language and one component library across all roles.
- Task-based navigation instead of exposing every backend entity as a peer page.
- Adaptive presentation at the existing 600, 1024 and 1440 pixel breakpoints.
- Progressive disclosure: hub, filter, detail, then sensitive action.
- Existing routes retained as deep links and compatibility entry points.
- Existing state and API clients retained as the canonical data and mutation layer.
- Independent role flags and immediate rollback to the current UI.
- Security, privacy, accessibility and regression gates before any role is enabled.

## What this blueprint does not approve

- Deleting, renaming or redirecting legacy routes without parity evidence.
- Duplicating API clients, state stores or mutation logic for the new layout.
- Treating a hidden control as authorization.
- Showing unsupported modules as functional.
- Recasting the delegated mCare Assistant as an AI chatbot.
- Recasting the external token guest as a registered external-doctor account.
- Changing clinical workflow semantics through a generic action such as Resolve.
- Persisting new PHI caches, adding third-party analytics or exposing secrets in URLs.

## Product terminology that must remain unambiguous

### mCare Assistant

The current mCare Assistant is a human delegated operations role named `mcare_assistant`. It shares the `/admin/*` backend namespace and receives a subset of administrative abilities through 12 database-backed permission keys. It is not an LLM, voice assistant, clinical decision-support engine or automation bot.

Any future AI product must use a separate name, threat model, clinical-governance process, consent model and backend contract.

### External Clinical Access

The current external clinician is a token guest invited by one patient for one patient record. The guest enters an eight-character code or opens a time-limited link. There is no authenticated external-doctor account, caseload, inbox, profile, settings or persistent notification identity.

The approved baseline label is **External Clinical Access**. An account-based external-doctor portal remains a future backend project.

## Evidence-based status legend

| Badge | Meaning | Approval consequence |
|---|---|---|
| Existing - redesign | UI and backend/domain exist | Presentation may migrate behind a flag after parity tests |
| Partial - harden/extend | Related data exists but the requested end-to-end behavior is incomplete | Design may be approved, but enabling requires the named backend work |
| Future - not backed | No matching model, route, controller or reliable workflow exists | Concept belongs in the future backlog, not the implementation contract |
| Security gate | Capability exists but a material risk must be closed | No production cutover until the release gate is green |

## Current code truth

| Layer | Verified surface |
|---|---|
| Flutter named routes | 99 constants, wired through `main.dart` |
| Shared/pre-login routes | 10 |
| Patient routes | 21 |
| Doctor routes | 22 |
| Administrator routes | 24 |
| mCare Assistant routes | 22 |
| Laravel API routes | 171 routes reported by `php artisan route:list --path=api/v1 --json` on 2026-08-07 |
| Backend namespaces | `/auth`, `/external`, `/me`, `/patient`, `/doctor`, `/admin` |
| Assistant backend | Reuses `/admin`; there is no `/assistant` API namespace |
| External backend | Public token/code endpoints; no authenticated role |

## Existing domain map

The current application has real domains for users and health profiles, vitals and vital catalog, medications and doses, appointments, medical documents, conversations and messages, notifications and staff notification state, SOS, care requests and assignments, reports, meal plans, support, external access tokens, audit events, security incidents, announcements and settings.

The repository does not contain complete domains for laboratory orders/results, imaging orders/PACS, billing, payments, insurance, pharmacy inventory/dispensing, formal referrals, embedded telemedicine, AI/LLM workflows, backup operations, integration registries or user-facing API-key configuration.

## Requested capability truth matrix

| Capability | Admin | Assistant | Patient | Doctor | External access |
|---|---|---|---|---|---|
| Home/dashboard | Existing | Existing, permission-filtered | Existing | Existing | One-patient summary only |
| Users/people | Existing | Partial by grant | Own profile/care team | Assigned caseload | One shared patient |
| Alerts and SOS | Existing | Permission and privacy caveats | Existing | Assigned caseload | Not available |
| Appointments | No admin module | No module | Existing | Existing | Not available |
| Vitals | Catalog/alerts | By grant | Existing | Existing | Review and record |
| Medications/prescriptions | No central module | No central module | Existing | Existing | Review and assign |
| Documents | No central file manager | No central file manager | Existing | Assigned patient | Metadata review and upload |
| Messages | Existing | Existing with privacy caveat | Existing threads | Existing threads | Not available |
| Reports/analytics | Partial/Existing | By grant | Vital report requests | Clinical reports and local overview | Note/upload only |
| Laboratory | Future structured module | Future | Document category only | Future request workflow | Document metadata only |
| Imaging/radiology | Future structured module | Future | Document category only | Future request workflow | Document metadata only |
| Billing/payments/insurance | Future | Future | Future | Future | Future |
| Pharmacy inventory | Future | Future | Medication domain only | Prescription domain only | Not available |
| Telemedicine/video | Future service | Future | Appointment metadata/link only | Appointment metadata/link only | Future |
| AI assistant/CDS/voice | Future governed product | Future governed product | Future governed product | Future governed product | Not available |
| Backup/integrations/API config | Infrastructure/future privileged module | Not delegated | Not applicable | Not applicable | Not applicable |

## Experience vision

Every role should answer one primary question quickly:

- Administrator: What needs the platform team now?
- mCare Assistant: What work am I permitted to complete?
- Patient: What should I do for my care today?
- Doctor: Which assigned patient needs clinical attention now?
- External clinician: What did this patient share, and which scoped finding may I add?

## Design principles

1. One component, many contexts. Role configuration changes content and accent, not implementation ownership.
2. Show the next safe action before secondary metrics.
3. Reveal the minimum necessary PHI at each layer.
4. Never use color as the only carrier of clinical meaning.
5. Preserve route and contract compatibility throughout migration.
6. Separate current functionality from future product ideas visually and textually.
7. Make sync freshness truthful; never infer whole-platform health from one successful poll.
8. Design failure, stale, revoked and permission-changed states as first-class screens.
9. Keep destructive and clinical actions typed, confirmed, audited and idempotent.
10. Optimize layout by available content width, not full-screen width.

## Approval outcome

Stakeholder approval authorizes Phase 0 baseline work and the additive Administrator pilot behind a disabled-by-default feature flag. It does not authorize production enablement. Each later role requires its own visual, security, contract, accessibility and UAT sign-off.

