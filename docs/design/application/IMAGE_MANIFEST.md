# Visual Asset and Prompt Manifest

## Usage

All assets in `assets/mockups/` are design-approval visuals. They contain fictional sample data and do not authorize unsupported functionality. Written screen, backend, validation, accessibility and security specifications are authoritative.

New assets were generated with the built-in image generation tool in `ui-mockup` mode. Targeted corrections used `precise-object-edit`. No CLI/API fallback was used.

## Final visual prompt set

| Asset | Final prompt intent | Status note |
|---|---|---|
| `shared-auth-responsive.png` | Responsive triptych with phone login, tablet patient onboarding and desktop login; patient-only self-registration, visible labels and privacy-focused shared form language | Existing - redesign |
| `shared-design-system-board.png` | Shared role accents, semantic states, type, buttons, fields, chips, cards, tables, dialogs, sheets, navigation, empty/loading/offline/error/success and light/dark specimens | Token values in written chapter are authoritative |
| `admin-home-mobile-v2.png` | Compact Guided Home with truthful freshness, privacy-minimized critical-alert action and Home/Work/People/More navigation | Existing - redesign |
| `admin-home-desktop-v2.png` | Expanded Guided Home with privacy-safe activity, counts rather than unsupported whole-system health, and the same four destinations | Existing - redesign |
| `admin-work-mobile.png` | Ranked compact Work queue with typed task summaries and filters | Existing - redesign; written command map authoritative |
| `admin-work-tablet.png` | Medium master-detail Work layout | Existing - redesign |
| `admin-people-mobile.png` | Compact Patients/Staff directory concept | Existing - redesign |
| `assistant-home-desktop.png` | Human delegated-staff Home with recommended work, freshness and an access summary; no AI/chatbot controls | Existing - redesign |
| `assistant-work-mobile.png` | Permission-aware compact Work queue with privacy-minimized summaries and Home/Work/People/More | Existing - redesign |
| `patient-home-mobile-v2.png` | Patient daily care plan, vital/dose/visit actions, help/SOS and Home/Health/Care/More | Existing - redesign |
| `patient-vitals-desktop.png` | Expanded seven-day vitals, assigned measurements, recent readings and report request | Existing - redesign; sample values only |
| `doctor-home-mobile-v2.png` | Assigned-caseload priorities, clinical action summaries and Home/Work/Patients/More | Existing - redesign |
| `doctor-patient-workspace-desktop.png` | Assigned-patient overview with monitoring, alerts, timeline, existing actions, SOS summary and messages | Existing - redesign; not a formal EHR encounter |
| `external-access-mobile.png` | Time-limited link/code gate for one record with no account registration or global navigation | Target after external security hardening |
| `external-workspace-desktop.png` | One-patient Summary/Vitals/Medications/Documents review plus typed Add finding actions and End session | Target after scope/session/audit hardening |

## Exact shared constraints used across prompts

- Realistic shippable Flutter product UI, not concept art.
- Accessible contrast, visible labels and 44-48 px control feel.
- Status uses icon plus text and never color alone.
- White/neutral surfaces with restrained role accent.
- Critical red and warning amber retain universal clinical meaning.
- No glass blur behind dense content.
- No fake diagnosis, unsupported system-online claim or fabricated trend claim.
- No AI controls unless a future governed AI product is separately approved.
- No watermark.
- Existing route/backend capabilities only, except external target-scope visuals explicitly marked as security-gated.

## Source and edit lineage

The five original Admin visuals were copied from `docs/design/admin/` into this self-contained application package. The mobile and desktop Admin Home assets received targeted copy corrections and were saved as `-v2` siblings. Patient and Doctor Home assets received target-navigation corrections and were also saved as `-v2` siblings. Original files remain available for comparison and were not overwritten.

