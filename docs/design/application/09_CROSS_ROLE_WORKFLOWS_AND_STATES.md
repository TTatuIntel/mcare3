# 09 — Cross-Role Workflows, Shared Components and State Behavior

## 1. Purpose and non-duplication rule

This chapter defines the workflows that cross role boundaries: notifications, messaging, SOS, documents, search, profile and settings. The goal is one recognizable interaction language across Patient, Doctor, Administrator and mCare Assistant while retaining the correct server owner, scope and command for each role.

**Golden rule:** share presentation primitives and interaction contracts; do not merge authorization domains or create generic mutations. A notification is not an alert, an SOS notification is not the SOS event, a document row is not permission to stream the file, and a visible button is not authorization.

The mCare Assistant in the current repository is a delegated human operations role with explicit permission keys. It is not an AI assistant or clinical decision engine. Any future AI feature needs a separate clinical-safety, data-governance and backend design; it must not be implied by assistant-role screens.

External clinical access uses selected shared visual primitives but does not join the authenticated role shell or state stores. Its one-patient capability is specified in [08_EXTERNAL_CLINICAL_ACCESS.md](08_EXTERNAL_CLINICAL_ACCESS.md).

## 2. Role and backend ownership matrix

| Domain | Patient | Doctor | Administrator | mCare Assistant | External guest |
|---|---|---|---|---|---|
| Notifications | Own row-backed notifications | Session-derived/caseload staff awareness + persisted local read state | Own row-backed + client-computed operational items | Direct/capability-filtered operational items only | None |
| Messaging | Own conversations | Assigned/caseload conversations | Current endpoint provides platform oversight | Direct-participant conversations only | None |
| SOS | Trigger/update own event | Respond only for caseload patient | Platform response | Only with `can_access_emergency_location` | None |
| Documents | Own CRUD/stream/download | Caseload patient CRUD/stream/download | No current document API in admin patient detail | No current document API in assistant patient detail | Summary metadata + upload only through issued capability |
| Search | Local own-module filtering | Local caseload/module filtering | Local hydrated directory/work filtering | Local authorized hydrated filtering | None |
| Profile | Own account + patient health profile | Own account + specialty/licence | Own account | Own account | No account profile |
| Settings | Own preferences + patient privacy | Own preferences | Own preferences + separately authorized platform settings | Own preferences only; authorized ops tools separate | No settings |

### Minimum-necessary rule

- Patient scope is self-owned data.
- Doctor scope is the currently assigned caseload and explicit workflow relationships.
- Admin scope is not a reason to preload all PHI into every surface; detail is fetched on deliberate need.
- Assistant scope is the intersection of role, current capability, target/object policy and workflow relationship. A zero-grant assistant receives no clinical or emergency detail.
- External scope is one issued patient capability, current validity and, in the hardened target, explicit action scopes.

## 3. Shared application interaction architecture

```text
Role shell / guest shell
  |
  +-- Shared awareness layer
  |    |-- Notification bell + notification centre
  |    |-- Sync freshness / offline status
  |    `-- Generic privacy-safe push signal
  |
  +-- Canonical workflow layer
  |    |-- Conversations -> role-specific conversation repository
  |    |-- SOS -> canonical SosEvent repository and typed commands
  |    |-- Documents -> role/object-specific document repository
  |    `-- Search -> authorized source adapters
  |
  +-- Shared account layer
  |    |-- Profile/avatar/email/password
  |    `-- Personal settings/theme/language/channels
  |
  `-- Shared UI state layer
       |-- loading / refreshing / partial / empty
       |-- offline / stale
       |-- 401 / 403 / 404 / 409 / 422 / 423 / 429 / 5xx
       `-- success / expiry / revoked

Each repository -> existing canonical role endpoint -> server authorization/policy
```

Transport does not grant access. Polling, optional realtime events and push only cause the app to refresh canonical server state. The current session poller uses a normal 30-second cadence and an 8-second urgent cadence; configured realtime may accelerate delivery, but reconciliation and current authorization remain mandatory.

## 4. Current route map

| Experience | Patient | Doctor | Administrator | mCare Assistant |
|---|---|---|---|---|
| Notifications | `/patient/notifications` | `/doctor/notifications` | `/admin/notifications` | `/assistant/notifications` |
| Messages | `/patient/messages` | `/doctor/messages` | `/admin/messages` | `/assistant/messages` |
| Thread | `/patient/messages/thread` | `/doctor/messages/thread` | `/admin/messages/thread` | `/assistant/messages/thread` |
| SOS | `/patient/sos` | `/doctor/sos` | `/admin/sos` | `/assistant/sos` |
| Documents | `/patient/documents` | Inside patient chart/workspace | No current dedicated admin document route | No current dedicated assistant document route |
| Profile | `/patient/profile` | `/doctor/profile` | `/admin/profile` | `/assistant/profile` |
| Settings | `/patient/settings` | `/doctor/settings` | `/admin/settings` | `/assistant/settings` |

No current universal-search named route or backend endpoint exists. Search is module-local over already authorized/hydrated data. A target search overlay must therefore be introduced progressively and must not imply unavailable cross-module results.

## 5. Notifications and passive awareness

### 5.1 Product purpose

The notification centre answers `What changed or needs my awareness?` It is not a second Work queue and must not execute a clinical or operational resolution merely because a notification is marked resolved.

The role-aware bell routes to the correct notification page. Guests and external clinicians have no notification destination and the bell is absent/no-op.

### 5.2 Current backend sources

| Source | Current API | Ownership |
|---|---|---|
| Patient notification rows | `GET /patient/notifications`; `PATCH /patient/notifications/{id}/read`; `PATCH .../{id}/resolve`; `POST /patient/notifications/read-all` | Notification must belong to current patient |
| Admin/Assistant notification rows | `GET /admin/notifications`; `PATCH /admin/notifications/{id}/read`; `PATCH .../{id}/resolve`; `POST /admin/notifications/read-all` | Current user's rows; current admin owner check is broader and needs policy review |
| Client-computed staff awareness | `GET /me/notification-states`; `POST /me/notification-states`; `POST /me/notification-states/read-all` | Opaque `staff_*` key state per current user |
| Doctor awareness | Derived from doctor session/caseload and staff state endpoints | No dedicated `/doctor/notifications` REST group currently exists |
| Push device registration | `POST /fcm-tokens`; `DELETE /fcm-tokens` | Current authenticated user/device token |

The notification centre can merge row-backed items and computed staff items for presentation, but their identity/source remains typed. Row read-state, computed-item read-state, alert acknowledgment and SOS state must never be conflated.

### 5.3 Notification row specification

Each row presents:

- type icon plus textual category;
- title and minimum-necessary summary;
- created/relative time;
- unread state;
- resolved/archived awareness state when meaningful;
- one safe destination/action label.

Sensitive patient name, vital value, SOS location, ticket text or message body is absent from lock-screen push and may be fetched only after sign-in and capability/object checks. A generic push such as `Urgent mCare task — sign in to view` is preferred.

### 5.4 Interaction rules

1. Opening marks read after the item is rendered or through an explicit policy; a failed remote read-state update does not change the underlying task.
2. `Mark all read` changes awareness only.
3. `Resolve notification` archives awareness only. For an alert or SOS, the row opens the canonical detail and that workflow exposes its typed commands.
4. An unknown route/type fails closed and offers a safe inbox refresh, not a guessed destination.
5. Permission loss immediately removes restricted row content and closes its detail.
6. Unread badge semantics announce `3 unread notifications`, not `badge 3`.

### 5.5 Target responsive design

- Compact: filter chips (`All`, `Unread`, `Resolved`), single virtualized list, detail opens destination/full screen.
- Medium: list plus optional preview when content is nonclinical; clinical task still opens canonical detail.
- Expanded: bounded list with filter/sidebar and detail, while preserving one selected notification ID.
- Empty copy states `No notifications in this view`; it must not claim no clinical work exists.

## 6. Messaging and conversations

### 6.1 Current endpoint map

| Role | List source | Thread | Send | Mark read |
|---|---|---|---|---|
| Patient | Conversations in `GET /patient/session` | `GET /patient/conversations/{conversation}/messages` | `POST /patient/conversations/{conversation}/messages` | `POST /patient/conversations/{conversation}/read` |
| Doctor | `GET /doctor/conversations` | `GET /doctor/conversations/{conversation}/messages` | `POST /doctor/conversations/{conversation}/messages` | `POST /doctor/conversations/{conversation}/read` |
| Admin/Assistant | `GET /admin/conversations` | `GET /admin/conversations/{conversation}/messages` | `POST /admin/conversations/{conversation}/messages` | `POST /admin/conversations/{conversation}/read` |
| Admin/Assistant create | — | — | `POST /admin/conversations` with target `user_id` creates/finds a thread | — |

Patient ownership is by the conversation's `user_id`. Doctor access is direct participation or patient caseload. Current Assistant list/detail is limited to direct participation; current Admin list provides broad oversight. Those rules remain server-owned and require negative IDOR tests.

Current messages are body text only. There is no attachment, edit/delete, reaction, typing indicator, read-receipt-per-recipient, video call or external-guest messaging contract. The redesign must not expose those controls.

### 6.2 Conversation list

**Row:** participant/patient identity, role/specialty where supplied, last-message preview only when authorized, timestamp and meaningful unread count. Search/filter runs only over conversations already authorized for the role unless a secure server endpoint is added.

**Empty states:**

- Patient: `No conversations yet` plus care-team context where available.
- Doctor: `No conversations in your caseload`.
- Admin: `No conversations match these filters`.
- Assistant: `No direct conversations available` or access guidance; never preview admin-wide threads.

### 6.3 Thread and composer

**Header:** participant identity and relationship, Back, and no unbacked voice/video controls. **Timeline:** ordered by `sent_at`, clear sender grouping, date separators and accessible delivery state. **Composer:** multiline body, explicit Send, character counter using a conservative 4000-character UI maximum until all endpoints share a server maximum.

**Send state:** local bubble may appear as `Sending`, but becomes `Sent` only after 201. Failure stays visible with `Retry`/`Discard`; retry needs idempotency support to prevent duplicates. The user cannot submit whitespace or double-tap Send. Mark-read occurs after an authorized thread load.

**Privacy:** no message text in push, search analytics, route arguments, crash breadcrumbs or screenshots generated by the app. Admin oversight must be clearly labelled and audited according to policy rather than looking like direct participation.

### 6.4 Responsive behavior

- Compact: conversation list and thread are separate named routes; Back returns to previous scroll/search state.
- Medium: list/thread split when width and 200% text allow; otherwise compact flow.
- Expanded: persistent 320–400 px list and flexible thread; selected ID is route-safe and authorization-checked.
- Keyboard: Ctrl/Command+Enter may send only if explicitly documented; Enter behavior must preserve multiline accessibility. Escape closes auxiliary panels, not the thread.

## 7. SOS emergency workflow

### 7.1 Canonical state machine

```text
Patient trigger
  |
  +-- an active/acknowledged event already exists -> return existing event
  `-- none -> create ACTIVE -> notify authorized responders
                                  |
                                  v
                           ACKNOWLEDGED
                             /       \
                            v         v
                        RESOLVED   FALSE ALARM
```

Current accepted write statuses are `acknowledged`, `resolved` and `falseAlarm`. The target should enforce valid transitions, state version and idempotency server-side rather than trusting buttons or allowing a generic status patch from stale UI.

### 7.2 Current endpoint/route ownership

| Actor | Endpoint | Scope |
|---|---|---|
| Patient | `POST /patient/sos` | Create own event; kind `medical`, `accident`, `fall`, `panic` or `other`; optional location/note |
| Patient | `PATCH /patient/sos/{event}` | Own event only; update to acknowledged/resolved/falseAlarm |
| Doctor | `PATCH /doctor/sos/{event}` | Caseload patient only; audited response |
| Admin/Assistant | `GET /admin/sos-events?status=...` | Admin, or Assistant with `can_access_emergency_location` |
| Admin/Assistant | `PATCH /admin/sos-events/{event}` | Same emergency-location capability; audited response |

Doctor session supplies active caseload events; Admin/Assistant session and the explicit list supply permitted platform events. External guest has no SOS endpoint.

### 7.3 Patient SOS design

**Entry:** emergency action from dashboard/profile/alerts according to existing navigation; it need not become a permanent sixth bottom tab. **Trigger page:** emergency type, location consent/status, optional concise note, emergency-services disclaimer and a deliberate hold/confirm interaction that remains accessible without gesture-only dependence.

**Active page:** large `SOS active`, exact start time, location-sharing state, responder status, `Mark as resolved` and `False alarm` with confirmation. Repeat trigger does not create a second event. A network failure must never claim responders were notified; offer phone/emergency-service fallback based on approved regional content.

### 7.4 Staff SOS hub

**List/detail:** active first; status, patient, emergency kind, age of event, ownership/responder; location and note only after current authorization. Commands are `Acknowledge — responding`, `Resolve`, and `False alarm`; Doctor may open the authorized emergency patient context.

**Critical rules:**

- The canonical `SosEvent` controls resolution. Resolving a notification does not resolve the event.
- Assistant receives event/location only with current emergency-location capability; recipient/push/realtime queries must apply the same check.
- `/admin/sos` and `/assistant/sos` remain distinct role routes even though they share the view. Route-guard tests must prevent an Assistant from using an admin-only route alias.
- Push contains no patient name, note or coordinates.
- Location is not placed in generic app logs or route URLs.
- Clinical completion is not optimistic; the UI waits for authoritative success.

### 7.5 Failure and concurrency states

- 409/stale: another responder changed status; refresh and explain who/what changed when safe.
- 403: access was updated; purge event/location, close detail and return to safe Home/Work.
- Offline: retain last-known event with a prominent timestamp; disable state-changing command or require explicit online retry. Do not queue an SOS resolution silently.
- Duplicate command: idempotently return current state.
- Realtime disconnect: show `Reconnecting`/last update; continue urgent reconciliation polling.

## 8. Medical documents

### 8.1 Current capabilities

| Actor | Current capabilities | Canonical endpoints |
|---|---|---|
| Patient | View metadata from session; upload, edit/replace metadata/file, delete, authenticated stream/download | `/patient/documents`, `/patient/documents/{id}`, `/stream`, `/download` |
| Doctor | View from patient detail; upload, edit/replace, delete, stream/download for caseload patient | `/doctor/patients/{patient}/documents...` |
| Admin/Assistant | Current `GET /admin/patients/{patient}` returns identity/health/emergency contacts/assigned vitals, not document data; no admin document endpoint | Do not render document actions |
| External guest | Summary document metadata and upload only | `GET /external/{token}`, `POST /external/{token}/documents` |

### 8.2 Shared document presentation

`DocumentCard/Row` uses the same visual component everywhere but receives role-specific allowed actions:

- title;
- category (`labResult`, `prescription`, `imaging`, `discharge`, `consultationNote`, `other`);
- file type (`pdf`, `image`, `doc`, `other`);
- uploaded time/by;
- description and size where supplied;
- availability/processing status;
- explicit `Preview`, `Download`, `Edit`, `Delete` or no action from the repository.

An absent action is not merely hidden by role name; it is absent because the server contract/policy does not authorize it.

### 8.3 Upload/edit/delete interactions

- File picker clearly lists PDF, JPG/JPEG, PNG, DOC and DOCX with current 10 MB server maximum.
- Client validates early; server validates again.
- Upload shows choosing, validating, uploading, server processing/scanning in the hardened target, success and retryable/non-retryable failure.
- Replace/delete names the exact document and impact; delete waits for server success.
- A retry must not create a duplicate; adopt idempotency keys before reliable automatic retry.
- On 403/404, remove the unavailable metadata and close preview without revealing cross-patient existence.

### 8.4 Preview/download behavior

Web currently has authenticated byte fetching/preview support; native document opening is incomplete. The target component must show a platform capability state rather than a no-op. Until native secure open/download is implemented and tested, show `Preview is available on web` or provide a safe supported alternative.

Medical files require private encrypted storage, object authorization on every stream/download, magic-byte validation, quarantine/antivirus/CDR as appropriate, EXIF stripping, no-store/nosniff delivery, safe filenames and download audit. Current public-disk/cache behavior is a production hardening blocker, not a design feature.

## 9. Search and filtering

### 9.1 Current truth

There is no universal search API or named route. Current screens filter in-memory authorized data such as Doctor patients, Admin users/work and role conversations. Therefore the first design release must label module search according to its actual scope (`Search my patients`, `Search conversations`, `Search authorized people`).

### 9.2 Target progressive architecture

```text
SearchLauncher
  |
  +-- Phase A: destination/command search (static, capability filtered, no PHI)
  +-- Phase A: current-module search over already authorized snapshot
  `-- Phase B: server search endpoint
               |-- authenticated role + capability
               |-- object/team/caseload scope
               |-- minimum result fields
               `-- pagination, audit/abuse/privacy controls
```

Initial server-backed result types may be Patient, Staff, Work item and Platform destination only after their APIs/policies exist. The server filters before returning results; the client does not receive then hide unauthorized data.

### 9.3 Shared search component

- Persistent label and role/scope-specific placeholder.
- Debounce; cancel stale requests; minimum query length for remote PHI search.
- Result type, safe title, minimal subtitle and one destination.
- Keyboard Up/Down, Enter, Escape and visible focus.
- Recent searches disabled for PHI by default; no search term in URL, analytics, crash logs or generic audit text.
- Empty state quotes the filter category, not the raw sensitive query in telemetry.
- 403 purges results; 429 pauses; offline clearly limits search to the local authorized snapshot.

Do not add a search icon that opens an empty or demo-only global experience. Hide/disable it with explanatory text until at least one truthful authorized source exists.

## 10. Profile, account and settings

### 10.1 Shared account structure

```text
Account header / avatar
  |-- Profile and identity
  |-- Edit account
  |-- Security
  |    |-- Change password
  |    `-- Change email + verify
  |-- Personal settings
  |    |-- Appearance
  |    |-- Language
  |    `-- Notification channels/preferences
  |-- Role-specific safe links
  `-- Sign out
```

The detailed auth/account contract is in Chapter 03. Across role portals, the account sheet follows these invariants:

- no duplicate Profile row when the identity header already opens Profile;
- no duplicate Notifications row when the persistent bell already opens it;
- no duplicate primary-nav destination in quick actions;
- emergency entry remains deliberate and clearly labelled;
- platform configuration is never mixed with personal preferences;
- External guest receives none of this account structure.

### 10.2 Personal settings backend

`GET /me/settings` and `PATCH /me/settings` are shared by all authenticated roles. Current fields are:

- `theme_mode`: `light`, `dark`, `system` or null;
- `language_code`: string up to 12 characters;
- `notifications`: boolean-keyed JSON map;
- `privacy_share_with_care_team`: boolean;
- `privacy_allow_external_access`: boolean.

The server merges partial updates. Flutter also caches preferences locally for fast paint and asynchronously persists remote changes. Target UI must show `Saving`, `Saved`, `Offline — saved on this device` or `Could not sync` rather than silently treating a failed server write as complete.

Privacy preferences must not be shown as enforced access controls until the corresponding API policies consume them. Safety-critical alert delivery policy is server-owned; a toggle label such as `Cannot be silenced` is valid only when end-to-end enforcement is tested.

### 10.3 Role-specific content

- Patient: appearance, language, notification preferences, care-team sharing and external-access controls.
- Doctor: appearance, language, appointment/message/report preferences and clinical-alert delivery policy.
- Administrator: personal appearance/language/notification preferences; platform system settings remain admin-only in their own audited module.
- mCare Assistant: personal preferences only plus separately capability-gated operational destinations.

Dark mode uses semantic tokens across every shared component; role accent changes emphasis, not status meaning or component behavior.

## 11. Canonical UI state language

Every cross-role screen and component must define these states. An empty list is never used to mask an error or authorization failure.

| State / response | Shared visual behavior | Required data behavior |
|---|---|---|
| Initial loading | Structure-matched skeleton, no fake names/counts | Do not clear a valid prior snapshot until replacement succeeds |
| Background refresh | Keep content, show subtle `Updating` | Fetch into temporary snapshot; atomically apply success |
| Loaded | Show last-updated/freshness where operationally useful | Render only currently authorized fields/actions |
| Empty | Domain-specific explanation and safe next action | Confirm request succeeded and authorized collection is truly empty |
| Partial | Section-level error with retry; other sections remain usable | Track per-source success/failure; do not merge stale/fresh without labels |
| Offline | Banner `Offline — showing data from <time>` | Retain approved last-known data in memory; no new privileged fetch |
| Timeout/network | Retry panel; preserve safe input/selection | Do not label credentials, code or resource invalid |
| 401/419 session expiry | Blocking `Session expired`, route to sign in | Clear token, user snapshot, PHI stores, selections, files, push/realtime session |
| 403 access updated | `Your access was updated`; safe Home/parent route | Purge restricted data immediately; refresh capabilities; cancel in-flight detail |
| 404 unavailable | `This item is no longer available` | Avoid revealing cross-scope existence; remove stale row |
| 409 conflict/stale | Explain another update occurred; `Review latest` | Discard optimistic final state; refetch canonical object/version |
| 422 validation | Inline field errors + summary | Preserve safe values; do not retry automatically |
| 423 locked | Account status panel and recovery | Stop background protected calls and route through auth handling |
| 429 rate limited | Retry-later message/countdown if available | Respect `Retry-After`; no tight loop |
| 5xx | Stable error with Retry/support reference | Retain prior snapshot as stale; no raw exception |
| Expired/revoked capability | Access-ended page | Purge capability data/secret; replace navigation history |
| Mutation pending | Exact action progress; disable duplicate commands | One in-flight command per object/action |
| Mutation success | Confirm what changed without excess PHI | Merge authoritative response; schedule reconciliation |
| Mutation uncertain | `We could not confirm the result`; refresh before retry | Use idempotency/status lookup before repeating a clinical/financial write |

### Write and optimistic-update policy

- Awareness-only read state and reversible personal preferences may update optimistically with visible sync state.
- Message bubbles may use `Sending`, not `Sent`, before confirmation.
- SOS, alert resolution, medication, document deletion, role/permission, approval and other consequential commands are not optimistically finalized.
- Every future retryable command carries an idempotency key and, where mutable state matters, a server state version.

## 12. Data refresh, realtime and offline behavior

### 12.1 Refresh ownership

- Patient hydrates from `/patient/session` and targeted patient endpoints.
- Doctor hydrates from `/doctor/session`, targeted caseload detail and conversation endpoints.
- Admin/Assistant hydrate from `/admin/session` plus capability-specific endpoints.
- External guest hydrates only its token/session summary endpoint.

Widgets do not poll independently. One role session coordinator deduplicates refreshes, and targeted repositories refresh the affected object after mutation.

### 12.2 Realtime/push contract

```text
Push or realtime event (opaque reference, no PHI)
      -> confirm active session/capability
      -> fetch canonical authorized object/session delta
      -> reconcile typed store
      -> update bell/work/SOS UI
```

Realtime channel authorization must apply the same account, role, capability, caseload and target policies as REST. Disconnect does not clear known data; it changes freshness state and activates reconciliation. Reconnect never restores data for a revoked capability without refetching authorization.

### 12.3 Offline boundaries

- Patient may later receive an explicitly approved last-known dashboard cache, but current redesign must not imply full offline clinical writes.
- SOS trigger/resolution, medication, document upload/delete, approvals, permissions and messages are not silently queued.
- Draft text may remain in volatile memory during a transient failure; PHI drafts are not persisted by default.
- Logout, session expiry, permission revoke and external expiry clear offline/last-known restricted content.

## 13. Shared responsive patterns

| Component/workflow | Compact <600 | Medium 600–1023 | Expanded ≥1024 |
|---|---|---|---|
| Notification centre | Filters + one list; destination full screen | List/optional preview | Filter rail + list/detail |
| Conversations | List route -> thread route | Conditional split view | Persistent list + thread |
| SOS | Active card + history stack | List/detail when safe | Queue + persistent event detail |
| Documents | Cards + bottom-sheet actions | Cards/table toggle, side sheet | Table/grid + preview pane |
| Search | Full-screen overlay | Centred overlay | Command palette/anchored panel |
| Settings | Grouped list, forms in sheets/pages | Two-column groups | Bounded two/three-column settings canvas |
| Profile | Header + sections | Header beside sections | Bounded detail with account rail/sections |

Responsive layout never changes role scope, endpoint, validation or command. Selection, filters, scroll position and drafts survive resize. At 200% text, split views collapse rather than squeezing columns.

## 14. Shared component and repository plan

```text
frontend/lib/shared/
├── workflows/
│   ├── notifications/
│   │   ├── notification_repository.dart
│   │   ├── notification_source_adapter.dart
│   │   └── notification_components.dart
│   ├── messaging/
│   │   ├── conversation_repository.dart
│   │   ├── conversation_role_adapter.dart
│   │   └── conversation_components.dart
│   ├── sos/
│   │   ├── sos_repository.dart
│   │   ├── sos_command.dart
│   │   └── sos_components.dart
│   ├── documents/
│   │   ├── document_repository.dart
│   │   ├── document_access.dart
│   │   └── document_components.dart
│   └── search/
│       ├── search_source.dart
│       └── search_components.dart
├── account/                     existing shared account/profile pieces
├── state/                       normalized typed state, not role UI imports
└── widgets/
    ├── async_state_view.dart
    ├── sync_freshness_banner.dart
    ├── form_error_summary.dart
    └── adaptive_detail_host.dart
```

This is a target organization, not a required one-shot move. Migration starts by wrapping current APIs with interfaces and reusing existing widgets. Role folders compose shared components with thin route/config adapters; `shared/` never imports a role folder.

### Repository contract

Each repository exposes typed read models and typed commands, including:

- current capability/object scope;
- `allowedActions` from server when available;
- load/refresh state and last-success time;
- canonical ID and state version;
- exact failure class (auth, forbidden, unavailable, conflict, validation, rate-limit, network, server);
- authoritative mutation result.

No `resolveAnything(id)` or generic `openPatient(id)` API is allowed. SOS, notification, alert, support and security commands remain distinct.

## 15. Privacy, security and accessibility

### 15.1 Privacy and authorization

- Every ID from navigation, push, realtime, search or UI is untrusted and reauthorized server-side.
- Sensitive detail is fetched only after deliberate open; dashboards/lists use minimum summaries.
- PHI is prohibited in push/lock screen, URL, analytics, session replay, crash logs, generic activity feeds and service-worker cache.
- Search terms, message bodies, document titles, readings, diagnoses, locations and ticket text are never telemetry dimensions.
- 403/revocation purges the related data, not merely hides the widget.
- Sensitive reads/downloads/exports and emergency-location access are audited according to policy.
- Admin and Assistant abilities require object/target hierarchy and current scope in addition to a role or coarse permission key.

### 15.2 Accessibility

- All icon-only controls have names; badges convey meaning; decorative icons are excluded from semantics.
- Status uses text + icon + colour. Risk, unread and sync status remain distinguishable in colour-vision deficiencies.
- Minimum touch target is 48×48 on touch; visible keyboard focus meets contrast requirements.
- List rows expose one coherent semantic label and separate named actions.
- Live updates are polite; a newly active SOS follows a tested urgent-announcement policy and is not repeatedly announced on each poll.
- Split panes maintain logical Tab order: shell -> filters/list -> detail -> actions.
- Escape closes preview/detail before leaving the parent page; browser Back mirrors the visual hierarchy.
- Reduced motion disables nonessential transitions; loading skeletons do not pulse aggressively.
- Dark/light/system themes use semantic tokens and meet WCAG 2.2 AA contrast.

## 16. Safe implementation and migration sequence

1. Inventory/contract-test existing named routes, argument types, session payloads and all endpoints listed above.
2. Close P0 account, assistant scope, SOS recipient, IDOR, external and private-file security blockers that affect shared surfaces.
3. Introduce shared typed failure/state classes and centralized 401/403 handling without changing visual screens.
4. Add repository adapters around current notification, messaging, SOS, document, profile and settings APIs.
5. Extract/evolve presentation primitives one domain at a time; keep legacy role screens as route-compatible fallbacks.
6. Migrate Notifications first because commands are low consequence, while preserving the awareness/task distinction.
7. Migrate Messaging with role-specific repository policies and existing body-only contract.
8. Migrate Documents after private storage/authorized delivery and native capability states are ready.
9. Migrate SOS only after typed transition, capability-recipient and concurrency tests pass.
10. Introduce truthful Phase A search; defer cross-module PHI search until a secure server endpoint exists.
11. Consolidate account/settings presentation after save-state and server-enforcement semantics are explicit.
12. Roll out independently by role/domain feature flag; rollback switches the domain back to its legacy view without removing routes or APIs.

## 17. Required quality matrix

### Authorization and object-scope tests

For every notification, conversation, SOS event, document, search result and account operation test:

- unauthenticated;
- Patient owner and different Patient;
- assigned Doctor and unassigned Doctor;
- zero-grant Assistant;
- exact-grant Assistant;
- Administrator;
- External guest when applicable;
- valid object, wrong object type, cross-patient ID, deleted/stale ID.

Assert status, returned fields, emitted events/audits and database/file side effects — not just whether a button is hidden.

### State/concurrency tests

- Initial load, background refresh, partial source failure, offline and recovery do not flash false empty data.
- 401 clears every role/PHI store and protected route stack.
- 403 revocation removes content while a detail/upload/message is open.
- 404/409/422/423/429/5xx map to the specified visual and retry behavior.
- Double tap/retry cannot duplicate a message, SOS transition, upload or other consequential write.
- Poll, realtime and push duplicates reconcile to one canonical object.
- SOS simultaneous responders and patient revoke/expiry races are tested.

### Cross-platform/responsive tests

- 360×800, 390×844, 599×900, 600×960, 800×1024, 1024×768, 1440×900 and 1920×1080.
- Repeat high-risk views at 200% text, dark mode, reduced motion, keyboard-only and screen reader.
- Compact -> expanded resize retains selection/draft without duplicate fetch/mutation.
- Native document unsupported path is visible and actionable, never a no-op.
- Push/lock-screen snapshots and analytics payloads contain no PHI.

### Workflow parity tests

- Notification read/resolve never mutates underlying alert/SOS/task.
- All role message paths load, send and mark read through the canonical endpoint.
- SOS route/permission/state transitions match role and caseload/capability.
- Document action sets exactly match patient, doctor, admin/assistant and external capabilities.
- Settings merge partial updates and show server sync failure.
- Search never returns an unauthorized type/record or records a PHI query in URL/telemetry.

## 18. Acceptance criteria

- [ ] Notifications, messaging, SOS, documents, search, profile and settings use shared visual/interaction components without duplicated business logic.
- [ ] Every role continues to use its existing named routes and canonical endpoints during migration.
- [ ] Role and object scope are enforced server-side; zero-grant Assistant receives no restricted clinical/emergency data.
- [ ] Notification awareness state is separate from alert, SOS and task state.
- [ ] Messaging remains body-only until a new attachment/video contract is explicitly designed.
- [ ] SOS uses the canonical event, typed transitions, current authorization and non-optimistic clinical completion.
- [ ] Document actions exactly reflect current endpoint availability; Admin/Assistant and external guests do not receive unbacked preview/download controls.
- [ ] Search labels its real scope; no universal PHI search is claimed before a secure endpoint exists.
- [ ] Personal settings are separate from platform configuration and visibly report server sync state.
- [ ] Every domain implements loading, refreshing, empty, partial, offline, 401, 403, 404, 409, 422, 423, 429, 5xx, success and expiry/revocation where applicable.
- [ ] 401/403/revoke removes restricted state and route history, not merely visual widgets.
- [ ] No PHI or secret appears in push, URL, analytics, crash logs, generic caches or session replay.
- [ ] Compact, medium and expanded behavior is consistent at 200% text, dark mode, keyboard and screen reader.
- [ ] Feature flags can independently roll back each migrated domain without deleting legacy routes, APIs or stored data.

