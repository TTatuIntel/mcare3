# Unified Design System and Component Specifications

## Design-system objective

The current tokens and shared Flutter components remain the foundation. Design System v2 adds additive, opt-in variants for the new page families. Global theme or `GlassCard` changes are deferred because they would affect Patient, Doctor, Auth and External screens simultaneously.

![Shared mCare design-system specimen. Written token values in this chapter are authoritative.](assets/mockups/shared-design-system-board.png)

## Role accents versus clinical semantics

Role accent colors identify ownership and navigation. Semantic colors identify state. An Admin warning is amber and a Patient warning is also amber; purple or indigo must never replace risk meaning.

| Token | Current code value | Use |
|---|---|---|
| Patient accent | `#6366F1` | Patient navigation, selection and non-clinical emphasis |
| Doctor accent | `#057A55` | Doctor navigation, selection and non-clinical emphasis |
| Admin accent | `#7E3AF2` | Administrator navigation and selection |
| Assistant accent | `#E3A008` | Delegated staff navigation and selection |
| External accent | `#3B82F6` | Time-limited external session context |
| Ink | `#0F172A` | Primary light-mode text |
| Muted AA text | `#64748B` | Secondary light-mode text |
| Critical | `#EF4444` | Critical clinical state, SOS and destructive confirmation |
| Warning | `#F59E0B` | Needs-review state |
| Success | `#10B981` | Completed, normal or verified state |
| Information | `#3B82F6` | Neutral information |

The generated specimen is visual direction. The values above, sourced from `AppColors`, are implementation truth.

## Surface and dark-mode tokens

| Surface | Light | Dark |
|---|---|---|
| Scaffold | `#F6F7FB` | `#0B1120` |
| Primary surface | `#FFFFFF` | `#111827` |
| Alternate surface | `#F8FAFC` | `#1F2937` |
| Muted surface | `#F1F5F9` | `#182234` |
| Border | `#E2E8F0` | `#334155` |
| Strong border | `#CBD5E1` | `#475569` |
| Primary text | `#0F172A` | `#F8FAFC` |
| Secondary text | `#64748B` | `#E2E8F0` |

Dark mode is a full semantic mapping, not color inversion. Charts, focus rings, disabled states, elevation and status chips require separate contrast verification.

## Typography

The application keeps the existing Outfit family and `AppTypography` scale.

| Style | Target use | Current size/weight guidance |
|---|---|---|
| Display | Marketing or rare hero copy | 28-44, bold |
| Page title | Screen identity | `AppLayout.pageTitle`, bold |
| Section title | Group identity | `AppLayout.sectionTitle`, semibold |
| Body large | Important explanatory copy | 16, regular, 1.5 line height |
| Body | Default content | `AppLayout.body`, regular, 1.5 line height |
| Caption | Supporting detail | `AppLayout.caption`, regular |
| Button/link | Actions | Semibold; sentence case |
| Data value | KPI/vital value | Tabular figures where supported; unit never omitted |

Rules:

- Do not rely on one-line ellipsis for critical labels.
- At 200 percent text scale, cards grow and action groups wrap.
- Values and units stay together where possible.
- Plain language is preferred over internal queue or database terms.

## Spacing, radius and grid

The existing spacing scale is `4, 8, 12, 16, 24, 32, 48`. Standard radii are `8, 12, 18, 24` and pill. Page insets are 16 mobile, 24 tablet and 32 desktop.

Layout uses a 12-column desktop grid, 8-column tablet grid and 4-column mobile grid. Component gaps use the spacing scale. Cards do not stretch beyond a useful reading width simply because a window is wide.

## Elevation and visual restraint

- Primary surfaces use a border and a very soft shadow; blur is not the default.
- Clinical status is expressed with icon, label and optional tinted surface.
- Gradients are reserved for small brand or hero accents, never behind body text.
- Frosted glass is not introduced into high-density operational or clinical screens.
- Motion never communicates clinical urgency by itself.

## Interaction targets and focus

| Context | Minimum target | Additional requirement |
|---|---|---|
| Mobile/tablet touch | 48 x 48 px | 8 px minimum separation where targets are adjacent |
| Desktop pointer | 44 x 40 px practical minimum | Visible hover and focus states |
| Keyboard | Entire actionable surface | Enter/Space activation and logical tab order |
| Screen reader | Named role, value and state | Decorative icons excluded from semantics |

Focus uses a visible 2 px role-accent ring with sufficient offset. Critical state retains its semantic icon and label while focused.

## Core component library

| Component | Variants | Contract |
|---|---|---|
| App shell | Auth, Patient, Staff, External Guest | Presentation only; role/capability config is injected |
| Page header | Home, inner page, contextual patient/session | Title, optional subtitle, freshness, bell/avatar where allowed |
| Button | Primary, secondary, quiet, destructive, disabled, loading | One authoritative command; disables duplicate submission |
| Text field | Default, helper, error, read-only, search | Persistent label; server errors map to field or form summary |
| Card/surface | Action, summary, metric, detail, callout | Border-first; role accent is not clinical state |
| Status chip | Critical, warning, success, info, neutral, stale | Icon plus readable label; no color-only state |
| Filter chip | Single/multiple selection | 48 px touch target; selected state readable without color |
| Work item row | Typed task summary | Type, priority, status, time/SLA, minimum PHI, allowed navigation |
| Person row | Patient/staff/clinician | Identity, role/status, authorized contextual actions |
| Table | Sort, filter, select, paginate | Desktop only when tabular comparison matters; mobile becomes rows |
| Chart | Line, bar, categorical summary | Axis, units, legend, accessible text summary, honest missing data |
| Dialog | Confirm, warning, destructive | Focus trapped; safe default; reason field when policy requires |
| Sheet/drawer | Detail and typed action | Bottom sheet on compact, right drawer on expanded |
| Toast/banner | Success, error, stale, permission update | Does not replace a durable action receipt |
| Upload | Choose, progress, scan, success, failure | File type/size before selection; authorized delivery only |
| Pagination | Page and load-more | Server cursor/page semantics remain canonical |
| Empty state | No data, no matches, no permission | Explains why and offers only valid next action |
| Skeleton | Initial load and refresh | Preserves layout; never presents stale data as loading success |

## Buttons and action hierarchy

Each view has one primary action per decision area. Secondary actions are outlined or quiet. Destructive actions live in an overflow or final confirmation, not beside the primary action with equal weight.

Clinical actions follow: open detail -> verify context -> enter required reason/data -> confirm -> server response -> durable receipt. Lists do not expose an ambiguous generic Resolve button.

## Forms and validation

- Labels remain visible after entry.
- Required fields are marked in text, not color alone.
- Client validation improves speed; server validation is authoritative.
- Error summary receives focus after submit and links to invalid fields.
- Values use correct keyboard/input mode and units.
- Dates display local time but store/transmit the existing contract format.
- Unsaved changes require an explicit leave decision.
- Double submission is disabled while a request is in flight.
- A failed optimistic non-clinical action rolls back visibly; clinical completion is not optimistic.

## Lists, tables, filters and search

Large lists own their scroll and use builders/slivers. They do not sit as an eager Column inside a page-level scroll view.

Filters are expressed as plain-language chips with an accessible filter sheet for advanced criteria. Search runs only against an authorized, meaningful dataset. Search results do not reveal restricted entities through suggestions or counts.

Desktop tables become stacked information rows on compact screens. Essential identity and state remain visible; secondary columns move into the detail sheet.

## Charts and data visualization

- Every axis and unit is labeled.
- Threshold bands are described in text.
- Missing samples create a gap rather than a fabricated value.
- Unknown trends are omitted, not displayed as zero.
- Tooltips are keyboard accessible and have a textual equivalent.
- Role color is not used to encode clinical severity.
- Admin home shows counts and freshness, not unsupported whole-system health.

## Navigation components

Compact screens use four stable destinations. Medium screens use a compact rail. Expanded screens use an extended rail with the same sections. Child routes map back to a parent section so selection never disappears on a detail page.

The bell remains a header action only for roles with a notification destination. Profile and personal settings live in the avatar menu. SOS is always visible to Patient and clinical responders where authorized; it is not buried in More.

## Required states for every data surface

1. Initial loading.
2. Refreshing with prior safe data retained.
3. Ready with data.
4. Empty.
5. Filter has no matches.
6. Offline or stale with last-success time.
7. Recoverable request error.
8. Validation error.
9. Permission required or grant revoked.
10. Session expired.
11. Conflict/stale version.
12. Success receipt.

## Accessibility standard

The implementation target is WCAG 2.2 AA for web and equivalent mobile semantics. Required validation covers text scaling to 200 percent, keyboard-only use, screen readers, contrast, reduced motion, focus order, touch targets, error identification, chart alternatives and orientation changes.

## Motion

Use 120-240 ms transitions for context and 240-320 ms for sheets. Respect reduced-motion preferences. Pulsing is reserved for active critical state and must have a static icon/label equivalent. Background refresh never causes list items to jump while the user is acting.

## Component ownership and no-duplication rule

Shared components live under a new additive design-system or staff-hub namespace. Role folders compose them with configuration. Networking stays in existing API clients; state stays in existing stores; authorization stays on the server. A role-specific wrapper is allowed only to inject routes, accent, labels and capability policy.

