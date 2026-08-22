# 03 — Responsive Flutter Architecture

## 1. Architectural objective

Implement the Guided Operations Hub once in Flutter and adapt only layout and input affordances. Data models, state, authorization, routes, actions, copy, and analytics events remain shared.

## 2. Existing foundations to retain

- `RoleShell` is already the shared staff scaffold.
- `ResponsiveBuilder` already defines 600, 1024, and 1440 logical-pixel thresholds.
- `StaffDestinations` is the current navigation source.
- `StaffRouteConfig` and shared admin screens already reduce role wrappers.
- `AppColors`, `AppPalette`, `AppSpacing`, `AppTypography`, `AppMotion`, and `AppLayout` provide global tokens.
- `AdminApi`, `StaffState`, `SupportState`, `AdminSessionService`, and existing mutations remain the data/action layer.
- Navigator 1 named routes remain in place throughout the redesign.

## 3. Adaptive tiers

| Available content width | Navigation | Home | Work/People detail |
|---|---|---|---|
| `<600` compact | Four-item bottom bar | Single column, 2×2 goal cards | Route/full-screen or accessible bottom sheet |
| `600–1023` medium | Compact 72–88 px rail | One or two columns from local constraints | Optional list/detail only when local width is at least ~900 px |
| `1024–1439` expanded | 220–240 px extended rail | Two-column content | Persistent list/detail pane |
| `≥1440` wide | Same extended rail | Constrained 2–3 region layout | Master/detail with optional secondary pulse region |

Use `LayoutBuilder` after subtracting the rail. Do not choose grid columns using the full-screen `MediaQuery` width because a 1024 px screen with a 240 px rail has only about 784 px of content.

## 4. Shared composition model

Recommended shared modules:

```text
shared/staff_hub/
├── models/
│   ├── staff_hub_section.dart
│   ├── staff_work_item.dart
│   └── staff_dashboard_snapshot.dart
├── services/
│   ├── staff_work_item_composer.dart
│   └── staff_dashboard_snapshot_builder.dart
├── navigation/
│   ├── staff_hub_route_registry.dart
│   └── staff_hub_route_args.dart
├── views/
│   ├── guided_home_view.dart
│   ├── staff_work_view.dart
│   ├── staff_people_view.dart
│   └── staff_more_view.dart
└── widgets/
    ├── adaptive_staff_header.dart
    ├── goal_card.dart
    ├── work_item_tile.dart
    ├── adaptive_detail_host.dart
    ├── sync_status_chip.dart
    └── staff_surface_card.dart
```

Thin role configuration supplies accent, canonical routes, and capabilities. It must not duplicate view implementations.

## 5. Navigation contract

Introduce a typed section model rather than overloading doctor navigation:

```text
StaffHubSection
- id
- label
- icon
- entryRoute
- activeRoutes
- child entries/filters
- badge resolver
- visibility/capability predicate
```

Requirements:

- Admin and Assistant expose exactly Home, Work, People, More.
- Doctor navigation remains unchanged.
- A parent remains selected for any mapped legacy child route.
- A parent is visible when at least one authorized child is visible.
- An inaccessible child is absent; a stale direct route still receives a server check and a clear permission state.
- Complete-profile and force-password gates remain outside the hub.

## 6. Scrolling and virtualization

Current staff screens commonly place an eager `Column` inside the shell's `SingleChildScrollView`. Do not use that pattern for unified Work or People lists.

- Hub lists use `RoleShell(scrollable: false)`.
- Use `CustomScrollView`, `SliverList`, or `ListView.builder`.
- Keep filters/header pinned only when usability testing supports it.
- Preserve scroll position independently per hub/filter.
- Detail selection does not rebuild or refetch the whole list unnecessarily.
- Paginate directory and historical work; do not hydrate every record for layout convenience.

## 7. Adaptive detail behavior

One `AdaptiveDetailHost` owns selection:

- Compact: navigate to a detail route or present a full-height sheet with a stable route fallback.
- Medium when wide enough: list and detail side-by-side.
- Expanded/wide: persistent right pane.
- Browser Back/Escape closes detail before leaving the hub.
- Deep-link arguments select the correct filter and item only after role/capability validation.

The selected task executes the same typed command on every tier.

## 8. Design tokens

### Existing palette to reuse

- Primary ink: `#0F172A` / approved design ink `#172033`
- Admin accent: current `#7E3AF2`; mockup violet `#6250E8`
- Surface: `#FFFFFF`
- Scaffold: current `#F6F7FB`
- Success, warning, critical, and information tokens already exist.

Before changing the global admin accent, test patient/doctor/shared components. Prefer a staff-hub theme extension or token alias first.

### Recommended staff-hub dimensions

- Touch target: minimum 48×48 on compact/medium.
- Pointer control: minimum 40–44 high with visible focus and sufficient spacing.
- Body text: target 16; secondary 13–14 with AA contrast.
- Card radius: 12–16.
- Page insets: retain existing 16/24/32 scale.
- Content max width: 1280–1360 for the first version.
- Severity rail: 4 px plus icon/text label.

Current `AppLayout.controlHeight` is 40 and `bodyMedium` is 14. Do not change these globally in the first staff-hub PR. Introduce accessible staff-hub component defaults, measure regressions, then decide whether to promote them globally.

## 9. Surface treatment

- Use neutral white/dark surfaces with a fine border.
- Avoid applying blur/glass/gradient decoration to every card.
- Do not globally rewrite `GlassCard`, because it is shared by other roles.
- Introduce `StaffSurfaceCard` and migrate the hub deliberately.
- Reserve full-width coloured surfaces for genuine emergency state.

## 10. Input methods

### Touch

- Large hit areas and visible buttons.
- No swipe-only command.
- Destructive/sensitive actions require a labelled confirmation.

### Keyboard and pointer

- Logical Tab order: shell → filters → list → detail actions.
- Enter/Space activates controls; Escape closes sheet/detail.
- Visible focus ring at 3:1 contrast against adjacent colour.
- Hover is supplementary, never required to discover an action.
- Do not rely solely on the current custom `GestureDetector` button behavior; verify semantic button role and keyboard activation.

### Screen reader

- Announce task type, severity, person, age/due state, ownership, and action as one understandable group.
- Badge semantics include meaning: `1 urgent work item`, not `badge 1`.
- Decorative icons are excluded; meaningful icons have labels.
- Live updates use polite announcements except active SOS, which follows the tested urgent-announcement policy.

## 11. Responsive component rules

| Component | Compact | Medium | Expanded/Wide |
|---|---|---|---|
| Goal cards | 2×2 | 2×2 or 4 across | 4 across |
| Work filters | Scrollable segmented row | Wrapped/segmented | Fixed horizontal |
| Work item | Full-width tile | List tile | Master-list tile |
| Detail | Full screen/sheet | Conditional second pane | Right pane |
| People | List | List or list/detail | List/detail |
| More | Grouped cards/list | Two columns | Two/three columns |
| Platform pulse | Collapsed | Side card | Side card/column |

## 12. UI states shared across platforms

Every hub defines:

- Initial loading skeleton
- Refreshing without clearing current content
- Loaded
- Empty for authorized scope
- Partial data / one source failed
- Offline with last-success time
- 401/session expired
- 403/access updated
- Stale item / 409 conflict
- Server error with retry
- No capability for this area

The current session service clears buckets before a request and swallows many errors. The redesign must fetch into a temporary snapshot and atomically apply success, retaining a visibly stale last-known snapshot on recoverable failure.

## 13. Performance budgets

- First meaningful staff Home content should use the existing hydrated snapshot and avoid duplicate KPI calls.
- Lists virtualize and paginate.
- No blur filter on scrolling web lists.
- Avoid rebuilding the whole shell on every task-state change.
- Images/avatars use bounded dimensions and caching that never stores sensitive full documents.
- Repeated polls deduplicate requests and do not clear/flash content.

## 14. Responsive test sizes

Minimum automated viewport matrix:

- 360×800
- 390×844
- 599×900
- 600×960
- 800×1024
- 1024×768
- 1440×900
- 1920×1080 constrained content

Repeat key tests at 200% text scale, dark mode, admin, zero-grant assistant, partial-grant assistant, keyboard-only web, and reduced motion.

