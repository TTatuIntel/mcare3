<?php

namespace App\Http\Controllers\Api\V1\Admin;

use App\Http\Controllers\Controller;
use App\Models\Announcement;
use App\Models\AppNotification;
use App\Models\AuditEntry;
use App\Models\CareAssignment;
use App\Models\CareRequest;
use App\Models\SosEvent;
use App\Models\SupportTicket;
use App\Models\SystemSetting;
use App\Models\User;
use App\Models\VitalCatalog;
use App\Support\ApiResponse;
use App\Support\VitalAlertPayload;
use Illuminate\Http\Request;

/**
 * Single admin/assistant session payload — mirrors DoctorSessionController.
 */
class AdminSessionController extends Controller
{
    use ApiResponse;

    public function show(Request $request)
    {
        $actor = $request->user();

        $users = $this->whenPermitted($actor, 'can_create_users', fn () =>
            User::query()->orderByDesc('created_at')->limit(100)->get()
                ->map(fn (User $u) => $u->toApiArray())->all()
        );

        $approvals = $this->whenPermitted($actor, 'can_approve_healthworkers', fn () =>
            User::query()
                ->whereIn('role', ['doctor', 'mcare_assistant'])
                ->where('approval_status', 'pending_approval')
                ->orderByDesc('created_at')
                ->limit(200)
                ->get()
                ->map(fn (User $u) => [
                    'id' => (string) $u->id,
                    'name' => $u->fullName(),
                    'email' => $u->email,
                    'phone' => $u->phone,
                    'role' => $u->roleToClient(),
                    'specialty' => $u->specialty,
                    'license_number' => $u->license_number,
                    'status' => $u->approvalStatusToClient(),
                    'submitted_at' => $u->created_at?->toIso8601String(),
                ])->all()
        );

        $careRequests = $this->whenPermitted($actor, 'can_manage_care_requests', fn () =>
            CareRequest::with(['user', 'provider', 'assignedProvider', 'decider'])
                ->orderByDesc('created_at')
                ->limit(200)
                ->get()
                ->map(function (CareRequest $r) {
                    $arr = $r->toApiArray();
                    $arr['patient_name'] = $r->user?->fullName() ?? '';
                    $arr['provider_name'] = $r->provider_name ?? $r->provider?->name ?? '';
                    $arr['reason'] = $r->reason ?? '';

                    return $arr;
                })->all()
        );

        $assignments = $this->whenPermitted($actor, 'can_assign_patients', fn () =>
            CareAssignment::with(['patient', 'provider', 'assigner'])
                ->whereNull('ended_at')
                ->orderByDesc('assigned_at')
                ->limit(500)
                ->get()
                ->map->toAdminArray()
                ->all()
        );

        $audit = $this->whenPermitted($actor, 'can_view_activity_logs', fn () =>
            AuditEntry::orderByDesc('happened_at')
                ->limit(50)
                ->get()
                ->map->toApiArray()
                ->all()
        );

        $sosEvents = $this->whenPermitted($actor, 'can_access_emergency_location', fn () =>
            SosEvent::with('user')
                ->where('status', 'active')
                ->orderByDesc('triggered_at')
                ->limit(100)
                ->get()
                ->map(fn (SosEvent $e) => array_merge($e->toApiArray(), [
                    'patient_id' => (string) $e->user_id,
                    'patient_name' => $e->user?->fullName(),
                ]))->all()
        );

        $vitalCatalog = $this->whenPermitted($actor, 'can_manage_vital_catalog', fn () =>
            VitalCatalog::orderBy('vital_key')->get()->map->toApiArray()->all()
        );

        $announcements = $this->whenPermitted($actor, 'can_manage_advertising', fn () =>
            Announcement::query()
                ->orderByDesc('created_at')
                ->limit(50)
                ->get()
                ->map->toApiArray()
                ->all()
        );

        $systemSettings = $actor->role === 'admin'
            ? SystemSetting::orderBy('key')->get()->map(fn (SystemSetting $s) => [
                'key' => $s->key,
                'title' => $s->title,
                'description' => $s->description,
                'category' => match ($s->key) {
                    'sms_critical_alerts', 'push_notifications' => 'Notifications',
                    'patient_signup_open' => 'Access',
                    'audit_retention' => 'Data',
                    default => 'Runtime',
                },
                'value' => (bool) $s->value,
            ])->all()
            : null;

        $alerts = $this->systemWideAlerts();

        $supportTickets = SupportTicket::with('user')
            ->whereIn('status', ['open', 'inProgress'])
            ->orderByDesc('created_at')
            ->limit(100)
            ->get()
            ->map(function (SupportTicket $t) {
                $arr = $t->toApiArray();
                $arr['patient_name'] = $t->user?->fullName();
                $arr['patient_user_id'] = (string) $t->user_id;

                return $arr;
            })->all();

        $notifications = AppNotification::query()
            ->where('user_id', $actor->id)
            ->orderByDesc('created_at')
            ->limit(200)
            ->get()
            ->map->toApiArray()
            ->all();

        $activePatients = User::where('role', 'patient')
            ->where('approval_status', 'active')
            ->count();
        $openAlerts = is_array($alerts)
            ? collect($alerts)->where('resolved', false)->where('acknowledged', false)->count()
            : 0;

        return $this->success([
            'users' => $users,
            'approvals' => $approvals,
            'care_requests' => $careRequests,
            'assignments' => $assignments,
            'audit' => $audit,
            'sos_events' => $sosEvents,
            'vital_catalog' => $vitalCatalog,
            'announcements' => $announcements,
            'system_settings' => $systemSettings,
            'alerts' => $alerts,
            'notifications' => $notifications,
            'support_tickets' => $supportTickets,
            'kpis' => [
                'active_patients' => $activePatients,
                'open_alerts' => $openAlerts,
                'pending_approvals' => is_array($approvals) ? count($approvals) : 0,
                'open_care_requests' => is_array($careRequests)
                    ? collect($careRequests)->where('status', 'pending')->count()
                    : 0,
                'active_sos' => is_array($sosEvents) ? count($sosEvents) : 0,
                'open_tickets' => count($supportTickets),
            ],
        ]);
    }

    private function whenPermitted(User $actor, string $key, callable $fn): mixed
    {
        if ($actor->role === 'admin') {
            return $fn();
        }
        if ($actor->role === 'mcare_assistant' && $actor->hasAssistantPermission($key)) {
            return $fn();
        }

        return null;
    }

    /** @return list<array<string, mixed>> */
    private function systemWideAlerts(): array
    {
        $patientIds = User::where('role', 'patient')->pluck('id');
        if ($patientIds->isEmpty()) {
            return [];
        }

        $patients = User::whereIn('id', $patientIds)->get()->keyBy('id');

        return AppNotification::whereIn('user_id', $patientIds)
            ->whereIn('kind', ['vital_warning', 'vital_critical', 'sos'])
            ->orderByDesc('created_at')
            ->limit(200)
            ->get()
            ->map(function (AppNotification $n) use ($patients) {
                $patient = $patients->get($n->user_id);

                return VitalAlertPayload::alertToApiArray($n, [
                    'patient_id' => (string) $n->user_id,
                    'patient_name' => $patient ? $patient->fullName() : '',
                ]);
            })->all();
    }
}
