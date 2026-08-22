# mCare Complete Application Design Blueprint

This directory is the authoritative stakeholder-approval package for the proposed mCare presentation-layer redesign across:

- Administrator
- delegated human mCare Assistant
- Patient
- Doctor
- External Clinical Access

The package is verified against the current Flutter and Laravel repository. Existing, partial and future-not-backed capabilities are separated so a visual approval cannot silently expand backend scope.

## Primary deliverable

[Open the complete single PDF](../../../output/pdf/mcare-complete-application-design-blueprint.pdf)

The earlier Admin/Assistant-only blueprint under `docs/design/admin/` remains design history. This application-wide package supersedes it for approval decisions.

## Source chapters

1. [Executive vision and product truth](00_EXECUTIVE_AND_PRODUCT_TRUTH.md)
2. [Unified design system](01_UNIFIED_DESIGN_SYSTEM.md)
3. [Information architecture and responsive shells](02_INFORMATION_ARCHITECTURE_AND_RESPONSIVE_SHELLS.md)
4. [Shared authentication and account](03_SHARED_AUTH_AND_ACCOUNT.md)
5. [Administrator portal](04_ADMINISTRATOR_PORTAL.md)
6. [mCare Assistant portal](05_MCARE_ASSISTANT_PORTAL.md)
7. [Patient portal](06_PATIENT_PORTAL.md)
8. [Doctor portal](07_DOCTOR_PORTAL.md)
9. [External Clinical Access](08_EXTERNAL_CLINICAL_ACCESS.md)
10. [Cross-role workflows and states](09_CROSS_ROLE_WORKFLOWS_AND_STATES.md)
11. [Route/API/permission traceability](10_ROUTE_API_PERMISSION_TRACEABILITY.md)
12. [Security, privacy and clinical safety](11_SECURITY_PRIVACY_CLINICAL_SAFETY.md)
13. [Safe implementation roadmap](12_SAFE_IMPLEMENTATION_ROADMAP.md)
14. [Testing, UAT and rollback](13_TESTING_UAT_ROLLBACK.md)
15. [Approval and future backlog](14_APPROVAL_AND_FUTURE_BACKLOG.md)
16. [Image and prompt manifest](IMAGE_MANIFEST.md)

## Build

Use Python 3.11 because the current workstation's PDF dependencies are installed in that interpreter:

```powershell
py -3.11 docs/design/application/build_complete_application_pdf.py
py -3.11 docs/design/application/render_complete_application_pdf.py
```

The builder:

- reads all Markdown chapters;
- includes the approved high-fidelity visual set;
- generates a complete 99-route screen atlas directly from `route_names.dart`;
- fails if the route count changes without documentation review;
- writes `output/pdf/mcare-complete-application-design-blueprint.pdf`.

Rendered QA pages and contact sheets are temporary under `tmp/pdfs/` and are not product assets.

## Approval and implementation boundary

This package authorizes design review and, after sign-off, Phase 0 baseline work. Runtime cutover remains feature-flagged and gated by security, route/API compatibility, accessibility, responsive, UAT and rollback evidence. No existing route or workflow should be removed during the compatibility period.

