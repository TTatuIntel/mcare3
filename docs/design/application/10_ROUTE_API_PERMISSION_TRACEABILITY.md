# Route, API, State and Permission Traceability

## Traceability rule

Every implemented screen must have one manifest row that identifies its existing route, target parent, state owner, backend contract and authorization boundary. The generated PDF screen atlas is sourced from the same route file and is validated to contain all 99 constants.

## Backend namespaces

| Prefix | Caller | Authority |
|---|---|---|
| `/api/v1/auth/*` | Public or authenticated user depending endpoint | Throttles, Sanctum where required, account-state policy target |
| `/api/v1/external/*` | Token/code guest | Token expiry/revoke and write throttles; target adds scoped portal session |
| `/api/v1/me/*` | Any authenticated account | Own settings and notification state |
| `/api/v1/patient/*` | Patient | Sanctum, patient role, object ownership |
| `/api/v1/doctor/*` | Doctor | Sanctum, doctor role, active caseload/object scoping |
| `/api/v1/admin/*` | Admin and delegated Assistant | Sanctum, role middleware and `permission:*`; selected routes Admin-only |

There is no assistant API prefix and no authenticated external-doctor prefix.

## Shared authentication and account trace

| UI family | Routes | Primary contracts |
|---|---|---|
| Entry/login | `/`, `/home`, `/login` | login, Google, Apple, `/auth/me` |
| Patient registration | `/register` | register; patient-only self-registration |
| Email verification | `/verify-email` | OTP verification/resend behavior |
| Recovery | `/forgot-password`, `/reset-password` | forgot/reset password |
| Staff invitation | `/accept-invite`, `/pending-approval` | accept invite and approval state |
| Profile gates | `*CompleteProfile`, `*ForcePassword` | profile update/change-password contracts |
| Personal settings | role settings/profile routes | `/me/settings`, profile/avatar/email/password contracts |

## Patient domain trace

| Domain | Current routes | State owner | Backend family |
|---|---|---|---|
| Session/Home | `/patient` | Multiple stores via patient session sync | `GET /patient/session` |
| Onboarding/profile | onboarding, profile | `AuthState`, `ProfileState` | patient profile/onboarding/contact endpoints |
| Vitals | vitals, detail, history, week | `VitalsState` | patient vitals and tracked-vitals endpoints |
| Medication | medications and detail | `MedicationsState` | medications and medication-dose endpoints |
| Visits | appointments and detail | `AppointmentsState` | patient appointments endpoints |
| Documents | documents | `DocumentsState` | create/update/delete/stream/download |
| Messages | list and thread | `MessagesState` | conversation thread/send/read |
| Care team | care-team | `CareState` | providers and care requests |
| Notifications | notifications | `NotificationState` | index/read/resolve/read-all |
| Support | support and detail | `SupportState` | create/reply/close |
| SOS | sos | `SosState` | trigger/update |
| Vital reports | sheet entry from vitals | `VitalReportState` | create/cancel request |
| External links | sheets in Care Team/Settings | external access state/service | list/create/revoke |

## Doctor domain trace

| Domain | Current routes | State/data | Backend family |
|---|---|---|---|
| Session/Home | `/doctor` | `StaffState` session hydration | `GET /doctor/session` |
| Work/action inbox | inbox, alerts/detail, visits, SOS | session-composed typed items | alerts, requests, appointments, SOS endpoints |
| Caseload | patients, patient chart | assigned patient workspace | doctor patient detail/scoped domain endpoints |
| Monitoring | vitals and template | readings/catalog/assigned vitals | doctor vital endpoints; patient threshold persistence is partial |
| Prescriptions | prescriptions | scoped prescriptions | issue/revoke |
| Reports | reports/editor | report state/service | create/update/publish/delete |
| Appointments | appointments | scoped appointments | list/create/update |
| Messages | messages/thread | `MessagesState` | doctor conversation endpoints |
| Notifications | notifications | session-computed and persisted state | notification-state endpoints |
| Account | profile/settings | auth/settings state | shared auth and `/me/settings` |

## Admin and Assistant domain trace

| Work/person domain | Existing API operations | Assistant authority |
|---|---|---|
| Alerts | list, acknowledge, typed resolve | Current baseline has privacy caveats; target explicit alert capability |
| SOS | list, respond/resolve | `can_access_emergency_location` |
| Approvals | list, approve, reject, request info, credential upload/stream | `can_approve_healthworkers` |
| Care requests | list, route, cancel | `can_manage_care_requests` |
| Assignments | list, create, delete | `can_assign_patients` |
| Users/patients | list/create/detail/status/password/unlock/invite | Current `can_create_users` is too coarse; target split abilities |
| Role changes | change role | `can_change_user_types`; sensitive hierarchy must be constrained |
| Register privileged roles | admin/assistant creation | `can_register_admin`, `can_register_assistant` with stronger policy |
| Assistant grants | list/update permissions | Admin only |
| Support | list/reply/assign/resolve/close/reopen | Currently baseline; target view/action scope capabilities |
| Messages | conversations/thread/send/read | Currently baseline; target explicit communication scope |
| Audit/analytics | list/export/KPIs/timeseries | `can_view_activity_logs` |
| Security | list/resolve | `can_view_security_incidents` |
| Announcements | CRUD/publish | `can_manage_advertising` |
| Vital catalog | CRUD | `can_manage_vital_catalog`; clinical governance hardening required |
| System settings | read/update | Admin only |

## Current 12 Assistant permission keys

1. `can_approve_healthworkers`
2. `can_manage_care_requests`
3. `can_assign_patients`
4. `can_create_users`
5. `can_change_user_types`
6. `can_register_admin`
7. `can_register_assistant`
8. `can_view_activity_logs`
9. `can_view_security_incidents`
10. `can_access_emergency_location`
11. `can_manage_advertising`
12. `can_manage_vital_catalog`

The UI filters by these keys during the compatibility phase, but the release plan proposes finer capabilities because several current grants cover unrelated or high-impact actions.

## Canonical typed commands

Work items must map to the underlying aggregate and endpoint:

- Alert acknowledge is not alert resolution.
- Resolving a notification is not resolving its underlying alert.
- An SOS notification is not the `SosEvent` state machine.
- Security-incident acknowledgement is not SOS completion.
- Approval accept/reject/request-info are distinct commands.
- Support resolve, close and reopen are distinct commands.
- Assignment create/delete is not a generic work completion.

The work adapter may rank and route. It must delegate mutation to existing state/service methods until a versioned contract is introduced.

## Additive target contract

The first UI can compose work from existing session stores. A later additive contract may return:

- redacted counts;
- three to five privacy-minimized task summaries;
- task `type`, stable id and state version;
- `allowed_actions` from the server;
- capability version and session expiry;
- last successful server time;
- role-resolved UI feature flag.

Old clients continue receiving the existing session response during the compatibility window.

## Feature flags

At minimum use independent runtime flags:

- `guided_admin_hub_enabled`
- `guided_assistant_hub_enabled`
- `guided_patient_hub_enabled`
- `guided_doctor_hub_enabled`
- `external_workspace_v2_enabled`

The server returns only the signed-in role's resolved flag. Missing or failed flag lookup defaults to false. A flag changes presentation, never authorization.

## Route preservation

No current route constant is removed in the migration. Proposed hub entry routes are additive. Legacy detail routes continue to accept their existing argument shapes, including SOS maps/strings, user identifiers, patient workspace sections and conversation/thread identifiers.

Phase 1 links hub rows into existing details. Only after parity may a legacy list route enter a new hub with an initial filter. Compatibility remains for at least one full mobile release after complete rollout.

## Unsupported module trace

Laboratory, imaging, billing, payments, insurance, pharmacy inventory, formal referral, embedded video, AI assistant, backup/recovery UI, integration registry and API-secret configuration have no complete current route/state/API/model chain. Their future concepts must not receive an implementation-ready trace row until backend and security design is approved.

