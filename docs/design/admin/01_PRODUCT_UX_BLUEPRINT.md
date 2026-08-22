# 01 — Product and UX Blueprint

## 1. Purpose

The Guided Operations Hub should make mCare feel smaller and easier without removing capability. It reorganizes the current backend-shaped collection of admin modules around the work a person is trying to complete.

The redesign must improve:

- time to recognize and begin urgent work;
- discoverability of routine tasks;
- consistency between phone, tablet, web, and desktop;
- safety of privileged and clinical actions;
- privacy on overview and directory surfaces;
- accessibility for keyboard, touch, screen-reader, and enlarged-text users.

## 2. Users

### Administrator

Has broad platform responsibility, including people, permissions, system configuration, audits, clinical catalog governance, safety events, and operational queues.

### mCare Assistant

Uses the same experience but only sees server-authorized capabilities. An assistant may have no delegated grants or any subset of the current 12 keys. Baseline capabilities are not assumed safe merely because the current UI exposes them; the security blueprint proposes finer server abilities.

### Occasional administrator

Uses mCare infrequently and needs goal-based language, recommended next actions, confirmation, and recovery guidance rather than a dense module catalog.

## 3. Primary user jobs

1. Respond to an emergency or abnormal vital safely.
2. Review and route requests.
3. Approve or manage a health worker.
4. Find a patient or staff member.
5. Manage care-team assignments.
6. Reply to support or direct messages.
7. Review platform status, analytics, audit, and security.
8. Configure controlled platform or clinical settings.

## 4. Current-state problems confirmed in code

- Admin supplies approximately 19 rail destinations while mobile exposes five primary items.
- Desktop renders all destinations in a non-scrollable rail, which can overflow and exposes the backend module structure.
- Mobile Quick Access and dashboard cards duplicate the bottom navigation.
- The same alert can be represented by the hero, KPI, Needs attention list, activity feed, and badge.
- Exact-route tab selection will break when many legacy routes become children of four hubs unless a route-to-section registry is added.
- Current forced two-column metric layouts and single-line ellipsis cause truncated labels.
- Current dashboard and assistant dashboard calculate similar attention/count information in multiple places.
- A general activity feed can reveal patient names/readings before the user deliberately opens a task.

## 5. Experience principles

### UX-01 — Goal first

Top-level labels describe user goals: Home, Work, People, More. Controller names and database entities remain implementation details.

### UX-02 — One item, one operational home

The full task appears once in Work. Home can show a redacted top-task preview and a count, but does not repeat the same detailed card in several sections.

### UX-03 — Calm by default, unmistakable when urgent

Most surfaces are neutral. Red and amber are reserved for real status. Severity always combines icon, text, and colour.

### UX-04 — Progressive disclosure

The shell shows four destinations. Filters reveal task categories. Detail panels reveal context. Rare or destructive actions appear only inside the authorized detail and require confirmation.

### UX-05 — Minimum necessary information

Home, badges, notifications, and People rows contain only the information needed to choose the next action. Clinical detail is fetched and shown only after an authorized open.

### UX-06 — One product across sizes

Mobile, tablet, web, and desktop use the same terms, data, permissions, commands, and components. Layout adapts; product behavior does not fork.

### UX-07 — Server truth

Flutter permission gates improve usability, but Laravel policies/middleware and scoped queries decide access. Counts, empty states, and cached data must never be used to infer authorization.

### UX-08 — Honest status

`Systems online` is shown only when backed by a defined health signal. Otherwise the UI reports data freshness: Updating, Updated X ago, Offline—showing last update, or Session expired.

## 6. Approved information architecture

### Home

- Dynamic greeting and role
- Sync freshness
- Urgency statement
- Four goal cards: Urgent care, People, Requests, Platform
- Up to three recommended next actions
- Collapsed platform pulse

### Work

- Unified, permission-aware task queue
- Initial filters: All, Urgent, Requests, Messages
- Secondary type filters when useful: SOS, Alerts, Approvals, Care, Assignments, Support, Conversations
- Sort by highest priority, oldest, due soon, or assigned to me
- Mobile detail sheet/full screen; tablet/desktop detail pane

### People

- Universal search by name, ID, email, or phone
- Patients and Staff segments; Assistant is a Staff filter, not another product area
- Patient detail: summary, permitted clinical context, documents, care team
- Staff detail: account, role, status, invite/security actions
- Assistant Access tab: admin-only permission management

### More

- **Insights:** Analytics, Audit/export, Security incidents
- **Communication and content:** Announcements and retained conversation shortcuts
- **Clinical setup:** Vital catalog
- **Platform:** System settings and runtime controls, admin-only
- **Account:** Profile, personal settings, security, help, sign out

### Global shell

- Search
- Notification bell
- Profile/avatar menu
- Active SOS indicator only when an authorized active event exists
- Data freshness/offline indicator

## 7. Capability consolidation

| Existing area | Guided location |
|---|---|
| Dashboard/Overview | Home |
| Alerts and SOS | Work → Urgent |
| Approvals, care requests, assignments | Work → Requests |
| Support tickets | Work → Messages/Support |
| Conversations | Work → Messages, with a global unread shortcut if user research requires it |
| Patients and Users | People |
| Assistant permissions | People → Staff → Assistant → Access |
| Analytics, Audit, Security | More → Insights |
| Announcements | More → Communication and content |
| Vital catalog | More → Clinical setup |
| System settings | More → Platform |
| Notifications | Header bell |
| Profile and personal settings | Avatar menu / More → Account |

No current API or route is removed by this grouping.

## 8. Priority and ranking model

Work ranking must be deterministic, tested, and based on server-authorized data.

Recommended order:

1. Active SOS requiring the signed-in user's authorized response.
2. Unacknowledged critical clinical alerts.
3. Overdue safety/clinical work.
4. Due-today approvals, care requests, and assignments.
5. Assigned support/conversation items with an SLA.
6. Routine work ordered by age.

Tie-breakers: server priority, due time, creation time, then stable ID. The client must not invent a clinical severity or merge a SOS notification with the underlying SOS event.

## 9. Core flows

### Handle an alert

`Home preview or Work → Alert detail → Acknowledge → Review context → Resolve with action and note`

Acknowledgement and resolution are distinct commands. Resolution is confirmed, single-submit, audited, and sent to the canonical alert endpoint.

### Handle SOS

`Authorized active-SOS indicator → Work / Urgent → SOS detail → Location/contact context → Respond/resolve`

SOS is never treated as an ordinary notification. Location remains behind the emergency-location capability.

### Approve a worker

`Work / Requests → Approval detail → Credential review → Approve, Reject, or Request information → Next item`

### Route care

`Work / Requests → Care request → Patient/provider context → Route or Cancel → Confirm assignment`

### Manage a person

`People → Search/filter → Person detail → Authorized contextual action`

### Configure the platform

`More → Platform or Clinical setup → Setting detail → Recent authentication/MFA when required → Reason and confirmation → Audit receipt`

## 10. Language rules

- Prefer verbs: Start, Review, Assign, Reply, Acknowledge.
- Use Requests instead of a list of backend resource names on Home.
- Use People rather than separate Patients and Users top-level labels.
- Avoid false reassurance. Never pair `Everything is under control` with active critical work.
- State why a disabled action is unavailable.
- Permission changes use: `Your access was updated.`
- Offline uses: `Offline — showing data from 14:32.`
- Unknown data is `Not available`, never a fabricated zero or fallback trend.

## 11. Product success measures

- A user can identify the highest-priority authorized task within five seconds.
- A routine task is reachable in two navigation decisions or fewer.
- No primary label truncates at supported sizes or 200% text scale.
- One underlying event produces one operational task.
- Unauthorized content is absent from payload, state, semantics tree, and UI.
- Mobile and desktop complete the same workflow with the same server command.
- Existing bookmarked routes continue to resolve during migration.

## 12. Non-goals for the first implementation

- Replacing named-route navigation with another router.
- Rewriting patient or doctor experiences.
- Introducing WebSockets as part of the visual redesign.
- Removing legacy routes immediately.
- Adding a generic Resolve command for different work types.
- Caching a combined PHI work queue offline.
- Globally restyling every existing card before the staff hub proves stable.

