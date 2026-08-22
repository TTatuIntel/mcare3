# Information Architecture, Navigation and Responsive Shells

## One application, five experiences

```text
Public entry and authentication
|
+-- Patient account ---------------- Home | Health | Care | More
|   `-- global bell and always-visible SOS
|
+-- Doctor account ----------------- Home | Work | Patients | More
|   `-- assigned-caseload boundary and clinical responder SOS
|
+-- Administrator ------------------ Home | Work | People | More
|   `-- global operational authority, subject to hardening policy
|
+-- mCare Assistant ---------------- Home | Work | People | More
|   `-- same shared staff UI, filtered by live server capabilities
|
`-- External Clinical Access ------- access gate -> one-patient workspace -> receipt/end
    `-- no global app navigation and no persistent account identity
```

Uniformity means one visual grammar, interaction pattern and component ownership. It does not mean exposing the same content or authority to every role.

## Canonical top-level navigation

| Role | Destination 1 | Destination 2 | Destination 3 | Destination 4 | Global actions |
|---|---|---|---|---|---|
| Admin | Home | Work | People | More | Search, bell, avatar |
| Assistant | Home | Work | People | More | Search when permitted, bell, avatar |
| Patient | Home | Health | Care | More | Bell, SOS, avatar |
| Doctor | Home | Work | Patients | More | Bell, assigned-patient search, SOS, avatar |
| External guest | None | None | None | None | Expiry and End session |

## Navigation philosophy

- A persistent destination represents a user goal, not a database table.
- A role keeps at most four persistent sections on compact screens.
- Filters handle sibling task types; contextual sections handle one patient/person.
- Header bell and avatar are not duplicated in the bottom bar.
- Rare controls live under More or an entity overflow.
- Details use a bottom sheet/full page on compact and a right panel on expanded screens.
- Existing named routes remain registered and map to the selected parent section.

## Admin and Assistant hierarchy

```text
Home
|-- freshness and urgent summary
|-- recommended next actions
`-- compact operational counts

Work
|-- Emergency/SOS
|-- Alerts
|-- Approvals
|-- Care requests
|-- Assignments
|-- Support
`-- Messages entry

People
|-- Patients
`-- Staff/users
    |-- account/status actions
    `-- Assistant access grants (Admin only)

More
|-- Analytics and audit
|-- Security incidents
|-- Announcements
|-- Vital catalog
|-- System configuration (Admin only)
`-- Profile, settings and help
```

Assistant parents are visible when at least one child is authorized. Inaccessible filters and actions are omitted. A live permission revocation closes restricted details, clears restricted presentation data and returns to a safe destination with an explanation.

## Patient hierarchy

```text
Home
|-- care plan today
|-- next vital, dose and visit
`-- help and SOS

Health
|-- Vitals and trends
|-- Medications and dose history
|-- Documents
`-- Vital report requests

Care
|-- Appointments
|-- Care team and care requests
`-- Secure messages

More
|-- Notifications entry
|-- Profile and health profile
|-- Settings and privacy
|-- External access management
`-- Support
```

The existing five patient routes remain valid. The four hubs are additive aggregation routes behind a patient-specific flag.

## Doctor hierarchy

```text
Home
|-- caseload summary
|-- urgent/next actions
`-- today

Work
|-- SOS and alerts
|-- Visits and appointments
|-- Action inbox and requests
|-- Reports due
`-- Messages

Patients
|-- Assigned directory
`-- Patient workspace
    |-- Overview
    |-- Monitoring (vitals, trends, alerts)
    |-- Care plan (Rx, medications, meals, assigned vitals)
    |-- Visits and notes (appointments, reports, timeline)
    `-- Records and communication (documents, messages)

More
|-- Schedule and reports
|-- Vital setup
|-- Profile
`-- Settings
```

The current 13 patient-workspace sections are grouped visually without deleting their routes, panels or state.

## External consultation hierarchy

```text
Access link or code
-> expiry and scope confirmation
-> one-patient summary
   |-- Summary
   |-- Vitals
   |-- Medications
   `-- Documents
-> Add a finding
   |-- Record vital
   |-- Consultation note
   |-- Assign medication (only if scoped)
   `-- Upload document (only if scoped)
-> receipt
-> End / Expired / Revoked
```

There is no patient switcher, global search, persistent inbox or account menu.

## Responsive breakpoints

The blueprint retains the existing centralized breakpoints to minimize regression.

| Tier | Width | Navigation | Content pattern |
|---|---:|---|---|
| Compact | `<600` | Four-item bottom navigation | Single column; full-height detail/sheets |
| Medium | `600-1023` | Compact 72 px rail | One or two columns based on local constraints |
| Expanded | `1024-1439` | 220-240 px extended rail | Two-column hubs; master-detail where useful |
| Wide | `>=1440` | Same extended rail | Max-width 1360-1440; optional third context pane |

External access uses the same content-width tiers but never adopts authenticated app navigation.

## Local-constraint rule

Responsive choice is based on the width remaining after the rail, not the full `MediaQuery` width. A grid uses `LayoutBuilder` and a minimum useful tile width. This avoids the current 1024 px problem where a 240 px rail leaves narrow four-column cards.

## Page-family layout recipes

| Family | Compact | Medium | Expanded/wide |
|---|---|---|---|
| Home | Ranked single column | Hero plus two-column actions | Main actions plus secondary overview |
| Work | Filter chips + list | List and optional preview | Master list + detail drawer/pane |
| People | Segmented patient/staff rows | List-detail optional | Directory + persistent detail |
| Health/records | Cards and horizontal section chips | Two-column summaries | Chart/table plus action/context rail |
| Messages | Conversation list then thread | Split view when space permits | Three-pane optional: list/thread/context |
| Settings | Grouped sections | Narrow centered form | Two-column categories, max readable width |
| External | Step-by-step | Centered workspace | Scope rail + review + action panel |

## Route compatibility and parent selection

A typed route registry maps every legacy route to:

- role;
- parent destination;
- optional initial filter;
- detail identifier/arguments;
- required capability;
- canonical fallback route;
- whether the route is a guard flow rather than a hub child.

Selected navigation state must use this registry instead of exact route equality. Complete-profile and force-password flows stay outside the main shell.

## Deep-link truth

Route constants are preserved, but a browser hard refresh does not currently guarantee login then return to the original task. `initialRoute`, bootstrap auth clearing and role guards can lose the target. The blueprint does not claim full deep-link restoration until an integration test passes.

If required, add an allowlisted pending-route resolver that normalizes route/query data, authenticates, verifies role and permission, then restores only an authorized in-app path. Never accept arbitrary return URLs.

## One-code architecture

```text
Existing API clients and state stores
            |
            v
Role-neutral view models/adapters
            |
            v
Shared page families and components
            |
            v
Role config: labels, accent, routes, capabilities
            |
            v
Compact / medium / expanded presentation only
```

Business logic, mutation sequencing and authorization never branch by viewport. Responsive code chooses only composition.

## Proposed shared modules

- `ScreenManifest` or `StaffHubRouteRegistry` for route family and active section.
- `StaffWorkItem` and composer for typed, ranked work summaries.
- `StaffDashboardSnapshot` for permission-filtered counts and freshness.
- `AdaptiveDetailPane` for compact sheet versus expanded drawer.
- `ConstraintGrid` for minimum-card-width layout.
- `SyncFreshnessState` for updated/syncing/offline labels.
- Role configs for Admin, Assistant, Patient and Doctor.
- Constrained `GuestShell` for external access.

These are additive presentation seams. They call existing state mutations and API clients rather than replacing them.

