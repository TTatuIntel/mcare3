# 02 — Screen and State Specifications

## 1. Shared shell

### Required elements

- mCare brand on Home and expanded layouts
- Current section title on inner views
- Universal search
- Notification bell with meaningful unread count
- Profile/avatar menu
- Sync freshness state
- Active-SOS indicator only for an authorized user when a canonical active SOS exists
- Four primary destinations: Home, Work, People, More

### Shell invariants

- Search, bell, and profile do not disappear because a child route is open.
- A legacy child route highlights its parent hub.
- Navigation never displays a destination with no authorized child.
- The shell never trusts its own visibility as authorization.
- Admin and Assistant use identical layout/component logic.
- The doctor and patient shells remain unchanged in the first rollout.

## 2. Home

### Purpose

Orient the user and start the next authorized task. Home is not an exhaustive analytics page or a second navigation menu.

### Content order

1. Greeting and role
2. Data freshness/system signal
3. Urgency statement
4. Goal cards
5. Recommended next actions
6. Collapsed platform pulse

### Urgency statement

| Condition | Copy | Treatment |
|---|---|---|
| Authorized active SOS | `Active SOS requires response` | Critical icon, text and red accent |
| Critical alert, no SOS | `1 urgent item needs attention` | Warning/critical semantics according to item |
| Noncritical work only | `4 tasks need attention today` | Violet/neutral |
| No due work | `No tasks need attention right now` | Neutral/success, without claiming all systems healthy |
| Offline | `Offline — showing data from 14:32` | Offline icon and amber/neutral |

### Goal cards

| Card | Opens | Badge rule |
|---|---|---|
| Urgent care | Work with Urgent filter | Count of authorized canonical SOS + urgent alerts only |
| People | People with last/default segment | Authorized attention count, not total population unless allowed |
| Requests | Work with Requests filter | Authorized pending/due request count |
| Platform | More | Show no badge unless a defined authorized platform action requires attention |

Do not infer permission from a `0`. Unauthorized counts should be absent/null and the card should be removed or worded without the count.

### Recommended next actions

- Maximum three on compact; four on expanded.
- Ranked by the shared Work comparator.
- Minimum necessary summary only.
- Exactly one visible primary action.
- Tapping the row opens detail; tapping the action opens the same detail with the intended command emphasized.
- Do not execute a sensitive or clinical command directly from Home.

### Platform pulse

Collapsed by default on compact. Permitted metrics may include:

- Active patients, only for authorized directory/analytics scope
- Open authorized work
- Median response, only when backend returns a real value
- Sync status

Unknown metrics are omitted or `Not available`; never use hard-coded fallback values.

## 3. Work

### Purpose

Present heterogeneous operational tasks in one ranked, filterable workspace while retaining type-safe server commands.

### Normalized presentation model

`StaffWorkItem` should contain at least:

```text
stableKey       = type + canonical aggregate ID
type            = sos | alert | approval | careRequest | assignment |
                  support | conversation | security
priority        = emergency | critical | high | normal | low
status          = typed server state
stateVersion    = server version/updated timestamp for conflict checks
title           = minimum necessary subject
summary         = redacted task reason
createdAt / dueAt
owner
capability
allowedActions  = server-authorized typed commands
legacyRoute + arguments
```

The presentation model does not own authorization or mutation logic.

### Filters

Primary filters:

- All
- Urgent
- Requests
- Messages

Expanded type filters appear only when useful and authorized:

- SOS
- Alerts
- Approvals
- Care
- Assignments
- Support
- Conversations
- Security

Assistant filters are the union of currently authorized children. If a grant is revoked, restricted filters/items disappear immediately and selection moves to the first safe filter.

### Sort and ownership

- Highest priority first
- Oldest first
- Due soon
- Assigned to me

Ownership selector:

- My work
- Unassigned
- All authorized

Server queries should eventually support pagination/filtering; first release may compose the existing hydrated state for small queues.

### Work row

Required visible fields:

- Icon + textual task type + severity colour
- Person/service subject, if permitted
- Concise reason
- Age/due state
- Owner/unassigned state
- One primary action

No swipe-only action. No vitals, diagnosis, location, credential, or ticket body beyond what is necessary to identify the task.

### Typed detail commands

| Type | Canonical commands |
|---|---|
| SOS | Open canonical SOS, respond/resolve through SOS endpoint; never resolve only its notification |
| Alert | Acknowledge; Resolve with action/note through alert endpoint |
| Approval | Approve, Reject, Request information, Upload/View credential |
| Care request | Route or Cancel |
| Assignment | Create or Remove assignment |
| Support | Reply, Assign, Resolve, Close, Reopen |
| Conversation | Open thread, Send, Mark read |
| Security | Acknowledge/resolve the exact underlying security object according to server contract |

Each item uses `allowedActions`; unknown types fail closed and link to their safe legacy view.

### Command safeguards

- Disable repeat submission while pending.
- Include idempotency key for writes when backend support lands.
- Include state version for conflict detection when backend support lands.
- Clinical completion is not optimistically finalized.
- 409/stale response refreshes detail and explains the conflict.
- Reason/notes are retained for actions that currently require them.
- Audit receipt/success confirmation includes what changed, not sensitive data.

## 4. Work detail

### Compact

- Full-height accessible sheet or named detail route
- Sticky action footer
- Back closes detail and preserves list/filter position

### Medium/expanded

- List on left, selected detail on right
- Empty selection shows guidance, not an arbitrary patient's data
- URL/route may encode an allowlisted type/ID for authenticated deep links

### Information order

1. Task type, severity, status, owner
2. Subject identity and minimum context
3. Event/request facts
4. Related care/team/credential context only when authorized
5. Audit/history summary when useful
6. Secondary and primary actions

## 5. People

### Purpose

Replace separate primary Patients and Users destinations with one searchable directory while keeping clinical and privileged actions contextual.

### Search

Search name, unique ID, email, or phone. Requirements:

- Debounced input
- Server pagination/query for production volumes
- Search terms do not enter analytics, crash logs, or URL query history unless explicitly protected
- Clear button and keyboard Escape behavior
- Empty results explain filters and allow reset

### Segments

- Patients
- Staff

Staff role filters: Doctors, Assistants, Admins. Assistant can appear as a direct chip in the responsive UI, but remains part of the Staff data model.

### Directory row

- Initials/avatar
- Name
- Unique ID
- Role label
- Account/work state
- Care-team name or next operational fact only when permitted
- Chevron/open affordance

No diagnosis, vital value, medication, address, location, credential, or ticket body in the generic row.

### Patient detail

Tabs/sections, permission-dependent:

- Overview
- Clinical summary
- Vitals
- Medications
- Documents
- Care team
- Activity/audit link where authorized

The current admin patient route is read-only. The redesign must not imply new mutation rights.

### Staff detail

- Account
- Role and approval status
- Invite/security state
- Authorized actions: create, status, reset, unlock, resend invite, role change
- Assistant-only Access tab for admin permission management

### Privileged action hierarchy

Assistant actions must be limited by target hierarchy as well as capability. An assistant must never modify an equal/higher-privilege user merely because a coarse capability is present. The exact rules are specified in the security blueprint and enforced server-side.

## 6. More

### Group layout

#### Insights

- Analytics
- Audit and export
- Security incidents

#### Communication and content

- Announcements
- Conversation shortcut/unread summary if Messages remains inside Work

#### Clinical setup

- Vital catalog, governed capability only

#### Platform

- System settings, admin-only
- Feature flags and operational configuration

#### Account

- Profile
- Personal settings
- Security/password
- Help/support
- Sign out

### Rules

- Group headings stay consistent across sizes.
- A group is omitted when it has no authorized child.
- Destructive/rare controls never execute from the More list tile.
- System and clinical setup screens show change reason, impact, and audit behavior.

## 7. Universal search

Initial searchable types:

- Patient
- Staff
- Work item
- Platform destination

Search results are capability-filtered at the server/source. The client cannot receive and then hide unauthorized PHI. Result types are labelled. Selecting a result uses the route registry and validates the target after authentication.

## 8. Notifications

- Bell is for passive awareness, not a duplicate Work queue.
- A notification may link to a canonical Work item.
- Marking a notification resolved must not resolve the underlying alert/SOS/task unless the specific canonical command says so.
- Push/lock-screen content uses generic copy for sensitive events.
- Notification detail is capability-filtered and fetched after sign-in.

## 9. Profile and account

Profile/avatar menu contains:

- Identity and role
- Profile
- Personal settings
- Security/change password
- Help
- Sign out

Force-password and complete-profile flows remain dedicated gates that cannot be bypassed by hub navigation.

## 10. Empty states

| State | Required behavior |
|---|---|
| No work | Explain that there is no authorized work; do not claim the platform is healthy |
| No permission | Explain required access and route to safe Home; no data preview |
| No people results | Show query/filter summary and Reset filters |
| No More tools | Show account/help only |
| Feature flag off | Render the current legacy experience |

## 11. Loading, refresh and offline

- Initial skeleton mirrors final structure without displaying fake names or numbers.
- Refresh keeps the previous snapshot visible and marks it Updating.
- Failed refresh retains prior snapshot and adds stale timestamp.
- 401 clears all role/PHI state and returns to login.
- 403 removes the affected capability data, closes detail, selects a safe filter, and shows `Your access was updated.`
- Network/5xx errors never masquerade as an empty queue.

## 12. Dark mode

The hub must use `AppPalette` semantic tokens, not hard-coded light colours. Status soft backgrounds use the existing dark equivalents. Mockups are light-theme references; light and dark must meet the same contrast and status-semantics requirements.

## 13. Telemetry without PHI

Allowed UI telemetry examples:

- hub viewed
- filter selected
- action started/succeeded/failed by task type
- time to first action
- layout tier

Do not emit patient names, identifiers, readings, message text, ticket text, location, credential names, search terms, raw route arguments, or external-access tokens.

