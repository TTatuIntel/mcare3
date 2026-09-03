<?php

namespace App\Services;

use App\Models\AppNotification;
use App\Models\Appointment;
use App\Models\AssistantPermission;
use App\Models\AuditEntry;
use App\Models\CareAssignment;
use App\Models\CareProvider;
use App\Models\CareRequest;
use App\Models\ClinicalReport;
use App\Models\MealPlan;
use App\Models\MedicalDocument;
use App\Models\Medication;
use App\Models\MedicationDose;
use App\Models\SosEvent;
use App\Models\SupportTicket;
use App\Models\User;
use App\Models\UserInvite;
use App\Models\VitalReading;
use App\Models\VitalReportRequest;
use App\Support\VitalLabels;
use Illuminate\Support\Carbon;

/**
 * Assembles the complete dossier for ANY account — patient, doctor, mCare
 * assistant, or admin — so staff never have to piece a person together from
 * four different screens before making a decision about them.
 *
 * The shape is deliberately uniform: every role returns `account`,
 * `application`, `security`, `timeline`, `activity`, and `stats`. Role-specific
 * blocks (`clinical`, `progress`, `practice`, `access`) are added on top and
 * are simply absent for roles they do not apply to, so the client can render
 * whatever it finds without role branching.
 */
class UserDossierService
{
    /** Recent-record caps — dossier is a summary view, not a bulk export. */
    private const READING_LIMIT = 400;

    private const ACTIVITY_LIMIT = 60;

    /**
     * [$selfView] is set when the person reading the dossier is its subject.
     *
     * The shape is identical either way — the client renders one layout — but
     * a patient reading their own record must not be shown a clinician's
     * unpublished working notes. A note is published when its author decides
     * it is ready to be read; until then it exists for the care team only, and
     * staff dossiers still show it because that is the point of their view.
     *
     * @return array<string, mixed>
     */
    public function build(User $user, bool $selfView = false): array
    {
        $user->loadMissing(['healthProfile', 'emergencyContacts', 'assignedVitals']);

        $dossier = [
            'account' => $this->account($user),
            'application' => $this->application($user),
            'security' => $this->security($user),
            'stats' => [],
            'timeline' => $this->timeline($user),
            'activity' => $this->activity($user),
        ];

        if ($user->role === 'patient') {
            $dossier['clinical'] = $this->clinical($user, $selfView);
            $dossier['progress'] = $this->progress($user);
            $dossier['stats'] = $this->patientStats($user, $dossier);
        } else {
            $dossier['practice'] = $this->practice($user);
            $dossier['access'] = $this->access($user);
            $dossier['stats'] = $this->staffStats($user, $dossier);
        }

        return $dossier;
    }

    // ------------------------------------------------------------------
    // Shared blocks
    // ------------------------------------------------------------------

    /**
     * Identity plus every date staff asked to see on one card — applied,
     * approved, verified, last sign-in, last profile edit.
     *
     * @return array<string, mixed>
     */
    private function account(User $user): array
    {
        return [
            'id' => (string) $user->id,
            'unique_id' => $user->unique_id,
            'name' => $user->fullName(),
            'first_name' => $user->first_name,
            'last_name' => $user->last_name,
            'initials' => $this->initials($user->fullName()),
            'email' => $user->email,
            'phone' => $user->phone,
            'role' => $user->roleToClient(),
            'avatar_url' => $user->avatarUrl(),
            'status' => $user->approvalStatusToClient(),
            'profile_complete' => $user->isProfileComplete(),
            'email_verified' => $user->email_verified_at !== null,
            'email_verified_at' => $user->email_verified_at?->toIso8601String(),
            // "Date of account opening" — the application date for staff roles.
            'created_at' => $user->created_at?->toIso8601String(),
            'updated_at' => $user->updated_at?->toIso8601String(),
            'account_age_days' => $user->created_at
                ? (int) $user->created_at->diffInDays(now())
                : null,
        ];
    }

    /**
     * How this person got onto the platform: the credentials they submitted
     * and the approval decision made on them.
     *
     * @return array<string, mixed>
     */
    private function application(User $user): array
    {
        $invite = UserInvite::query()
            ->where('user_id', $user->id)
            ->orderByDesc('created_at')
            ->first();

        return [
            'applied_at' => $user->created_at?->toIso8601String(),
            'specialty' => $user->specialty,
            'license_number' => $user->license_number,
            'has_credential_document' => $user->credential_document_path !== null,
            'credential_document_name' => $user->credential_document_name,
            'approved_at' => $user->approved_at?->toIso8601String(),
            'approved_by_name' => $user->approvedBy?->fullName(),
            'approval_note' => $user->approval_note,
            'rejected_at' => $user->rejected_at?->toIso8601String(),
            'rejection_reason' => $user->rejection_reason,
            'invite_sent_at' => $invite?->created_at?->toIso8601String(),
            'invite_expires_at' => $invite?->expires_at?->toIso8601String(),
            'invite_accepted_at' => $invite?->accepted_at?->toIso8601String(),
            'invite_pending' => $invite !== null && $invite->accepted_at === null,
        ];
    }

    /**
     * Login and account-safety facts. No secrets — hashes and raw tokens
     * never leave the server; only counts, timestamps, and provider links.
     *
     * @return array<string, mixed>
     */
    private function security(User $user): array
    {
        // Ten most recent shown; the count is taken separately so a busy
        // account does not report a capped "10 sessions".
        $sessionCount = $user->tokens()->count();
        $tokens = $user->tokens()
            ->orderByDesc('last_used_at')
            ->limit(10)
            ->get(['name', 'last_used_at', 'created_at']);

        return [
            'last_login_at' => $user->last_login_at?->toIso8601String(),
            'last_login_ip' => $user->last_login_ip,
            'login_count' => (int) $user->login_count,
            'must_change_password' => (bool) $user->must_change_password,
            'failed_login_attempts' => (int) $user->failed_login_attempts,
            'is_locked' => $user->isLocked(),
            'locked_until' => $user->locked_until?->toIso8601String(),
            'has_password' => $user->password !== null,
            'google_linked' => $user->google_id !== null,
            'apple_linked' => $user->apple_id !== null,
            'active_sessions' => $sessionCount,
            'last_session_used_at' => $tokens->first()?->last_used_at?->toIso8601String(),
            'push_devices' => $user->fcmTokens()->count(),
            'sessions' => $tokens->map(fn ($t) => [
                'name' => $t->name,
                'created_at' => $t->created_at?->toIso8601String(),
                'last_used_at' => $t->last_used_at?->toIso8601String(),
            ])->all(),
        ];
    }

    /**
     * Account lifecycle as a single ordered stream, so an admin can read the
     * whole history of a person top-to-bottom before acting on them.
     *
     * @return list<array<string, mixed>>
     */
    private function timeline(User $user): array
    {
        $events = [];

        $push = function (?Carbon $at, string $kind, string $title, ?string $detail = null) use (&$events) {
            if ($at === null) {
                return;
            }
            $events[] = [
                'at' => $at->toIso8601String(),
                'kind' => $kind,
                'title' => $title,
                'detail' => $detail,
            ];
        };

        $push(
            $user->created_at,
            'created',
            $user->role === 'patient' ? 'Account registered' : 'Application submitted',
            $user->unique_id,
        );
        $push($user->email_verified_at, 'verified', 'Email verified', $user->email);
        $push(
            $user->approved_at,
            'approved',
            'Application approved',
            $user->approvedBy?->fullName(),
        );
        $push($user->rejected_at, 'rejected', 'Application rejected', $user->rejection_reason);
        $push($user->last_login_at, 'login', 'Last sign-in', $user->last_login_ip);
        $push(
            $user->isLocked() ? $user->locked_until : null,
            'locked',
            'Account locked',
            $user->failed_login_attempts.' failed sign-in attempts',
        );

        // Staff decisions recorded against this account.
        $decisions = AuditEntry::query()
            ->whereIn('action', [
                'user.role_changed',
                'user.status_changed',
                'user.password_reset',
                'user.unlocked',
                'user.invite_resent',
                'approval.approved',
                'approval.rejected',
                'patient.vitals_assigned',
                'report.consent_granted',
                'report.issued',
            ])
            ->where('meta->target_user_id', $user->id)
            ->orderByDesc('happened_at')
            ->limit(40)
            ->get();

        foreach ($decisions as $entry) {
            $push(
                $entry->happened_at,
                'decision',
                $this->auditTitle($entry->action),
                $entry->actor_label,
            );
        }

        usort($events, fn ($a, $b) => strcmp($b['at'], $a['at']));

        return $events;
    }

    /**
     * Audit rows where this user is either the actor or the subject.
     *
     * @return list<array<string, mixed>>
     */
    private function activity(User $user): array
    {
        return AuditEntry::query()
            ->where(function ($q) use ($user) {
                $q->where('actor_user_id', $user->id)
                    ->orWhere('meta->target_user_id', $user->id)
                    ->orWhere('meta->patient_user_id', $user->id);
            })
            ->orderByDesc('happened_at')
            ->limit(self::ACTIVITY_LIMIT)
            ->get()
            ->map(fn (AuditEntry $e) => $e->toApiArray() + [
                'is_actor' => (int) $e->actor_user_id === (int) $user->id,
            ])
            ->all();
    }

    // ------------------------------------------------------------------
    // Patient blocks
    // ------------------------------------------------------------------

    /**
     * Everything clinical the platform holds on a patient — the record an
     * admin needs before assigning care, issuing a report, or fielding a call.
     *
     * @return array<string, mixed>
     */
    private function clinical(User $user, bool $selfView = false): array
    {
        $readings = VitalReading::where('user_id', $user->id)
            ->orderByDesc('recorded_at')
            ->limit(self::READING_LIMIT)
            ->get();

        $medications = Medication::where('user_id', $user->id)
            ->orderByDesc('active')
            ->orderByDesc('start_date')
            ->get();

        return [
            'health' => $user->healthProfile?->toApiArray(),
            'has_health_profile' => $user->healthProfile !== null,
            'emergency_contacts' => $user->emergencyContacts
                ->sortBy('priority')
                ->map->toApiArray()
                ->values()
                ->all(),
            'assigned_vitals' => $user->assignedVitals->pluck('vital_key')->values()->all(),
            'vitals_summary' => $this->vitalsSummary($user, $readings),
            'recent_readings' => $readings->take(60)->map->toApiArray()->values()->all(),
            'medications' => $medications->map(fn (Medication $m) => $m->toApiArray() + [
                'prescribed_by_name' => $m->prescribedByUser?->fullName() ?? $m->prescribed_by,
            ])->all(),
            'meal_plans' => MealPlan::where('patient_user_id', $user->id)
                ->orderByDesc('assigned_at')
                ->limit(60)
                ->get()
                ->map->toApiArray()
                ->all(),
            'appointments' => Appointment::where('user_id', $user->id)
                ->orderByDesc('scheduled_at')
                ->limit(60)
                ->get()
                ->map->toApiArray()
                ->all(),
            'documents' => MedicalDocument::where('user_id', $user->id)
                ->orderByDesc('uploaded_at')
                ->limit(60)
                ->get()
                ->map->toApiArray()
                ->all(),
            'sos_events' => SosEvent::where('user_id', $user->id)
                ->orderByDesc('triggered_at')
                ->limit(40)
                ->get()
                ->map->toApiArray()
                ->all(),
            'reports' => ClinicalReport::where('patient_user_id', $user->id)
                ->when($selfView, fn ($q) => $q->where('published', true))
                ->orderByDesc('created_at')
                ->limit(40)
                ->get()
                ->map(fn (ClinicalReport $r) => $r->toApiArray() + [
                    'author_name' => $r->author?->fullName(),
                ])
                ->all(),
            'alerts' => AppNotification::where('user_id', $user->id)
                ->whereIn('kind', ['vital_warning', 'vital_critical', 'sos'])
                ->orderByDesc('created_at')
                ->limit(40)
                ->get()
                ->map(fn (AppNotification $n) => [
                    'id' => (string) $n->id,
                    'kind' => $n->kind,
                    'title' => $n->title,
                    'body' => $n->body,
                    'read' => (bool) $n->read,
                    'created_at' => $n->created_at?->toIso8601String(),
                ])
                ->all(),
            'care_team' => CareAssignment::with(['provider', 'assigner'])
                ->where('patient_user_id', $user->id)
                ->orderByDesc('assigned_at')
                ->get()
                ->map->toAdminArray()
                ->all(),
            'care_requests' => CareRequest::with(['provider', 'assignedProvider', 'decider'])
                ->where('user_id', $user->id)
                ->orderByDesc('created_at')
                ->limit(40)
                ->get()
                ->map->toApiArray()
                ->all(),
            'vital_report_requests' => VitalReportRequest::where('user_id', $user->id)
                ->orderByDesc('created_at')
                ->limit(20)
                ->get()
                ->map->toApiArray()
                ->all(),
            'support_tickets' => SupportTicket::where('user_id', $user->id)
                ->orderByDesc('created_at')
                ->limit(20)
                ->get()
                ->map(fn (SupportTicket $t) => [
                    'id' => (string) $t->id,
                    'subject' => $t->subject,
                    'status' => $t->status,
                    'created_at' => $t->created_at?->toIso8601String(),
                ])
                ->all(),
        ];
    }

    /**
     * Per-vital statistics and direction of travel over the default 3 weeks.
     *
     * @param  \Illuminate\Support\Collection<int, VitalReading>  $readings
     * @return list<array<string, mixed>>
     */
    private function vitalsSummary(User $user, $readings): array
    {
        $assigned = $user->assignedVitals->pluck('vital_key')->all();
        $keys = array_values(array_unique(array_merge(
            $assigned,
            $readings->pluck('vital_key')->unique()->all(),
        )));

        $cutoff = now()->subDays(21);
        $out = [];

        foreach ($keys as $key) {
            $forVital = $readings->where('vital_key', $key)->values();
            $latest = $forVital->first();
            $recent = $forVital->filter(
                fn (VitalReading $r) => $r->recorded_at !== null && $r->recorded_at->gte($cutoff),
            )->values();

            // Trend = newest half vs oldest half of the 3-week window.
            $trend = 'flat';
            if ($recent->count() >= 4) {
                $half = (int) floor($recent->count() / 2);
                $newer = $recent->take($half)->avg('value');
                $older = $recent->slice($half)->avg('value');
                if ($older > 0) {
                    $delta = ($newer - $older) / $older;
                    $trend = $delta > 0.05 ? 'up' : ($delta < -0.05 ? 'down' : 'flat');
                }
            }

            $out[] = [
                'vital_key' => $key,
                'label' => VitalLabels::label($key),
                'unit' => VitalLabels::unit($key),
                'assigned' => in_array($key, $assigned, true),
                'latest_value' => $latest?->displayValue(),
                'latest_risk' => $latest?->risk,
                'latest_at' => $latest?->recorded_at?->toIso8601String(),
                'period_days' => 21,
                'readings_period' => $recent->count(),
                'average' => $recent->isEmpty() ? null : round((float) $recent->avg('value'), 1),
                'lowest' => $recent->isEmpty() ? null : round((float) $recent->min('value'), 1),
                'highest' => $recent->isEmpty() ? null : round((float) $recent->max('value'), 1),
                'in_range_pct' => $recent->isEmpty()
                    ? null
                    : (int) round($recent->where('risk', 'normal')->count() / $recent->count() * 100),
                'readings_total' => $forVital->count(),
                'trend' => $trend,
            ];
        }

        return $out;
    }

    /**
     * Engagement and adherence — the "is this patient actually doing the
     * programme" view that a summary card can lead with.
     *
     * @return array<string, mixed>
     */
    private function progress(User $user): array
    {
        $now = now();
        $doses = MedicationDose::where('user_id', $user->id)
            ->where('scheduled_at', '>=', $now->copy()->subDays(30))
            ->get();

        $due = $doses->where('scheduled_at', '<=', $now);
        $taken = $due->where('status', 'taken');
        $adherence = $due->count() > 0
            ? (int) round(($taken->count() / $due->count()) * 100)
            : null;

        $readings7 = VitalReading::where('user_id', $user->id)
            ->where('recorded_at', '>=', $now->copy()->subDays(7))
            ->count();
        $readings30 = VitalReading::where('user_id', $user->id)
            ->where('recorded_at', '>=', $now->copy()->subDays(30))
            ->count();

        // Consecutive days (counting back from today) with at least one reading.
        $days = VitalReading::where('user_id', $user->id)
            ->where('recorded_at', '>=', $now->copy()->subDays(90))
            ->orderByDesc('recorded_at')
            ->pluck('recorded_at')
            ->map(fn ($d) => $d?->toDateString())
            ->filter()
            ->unique()
            ->values()
            ->all();

        $streak = 0;
        $cursor = $now->copy()->startOfDay();
        // Allow the streak to start yesterday so a patient who has not logged
        // yet today does not read as "0-day streak" all morning.
        if (! in_array($cursor->toDateString(), $days, true)) {
            $cursor->subDay();
        }
        while (in_array($cursor->toDateString(), $days, true)) {
            $streak++;
            $cursor->subDay();
        }

        $lastReading = VitalReading::where('user_id', $user->id)
            ->orderByDesc('recorded_at')
            ->value('recorded_at');

        $appointmentsKept = Appointment::where('user_id', $user->id)
            ->where('status', 'completed')
            ->count();
        $appointmentsMissed = Appointment::where('user_id', $user->id)
            ->whereIn('status', ['missed', 'no_show'])
            ->count();

        // Engagement blends the three behaviours the programme depends on.
        $components = array_filter([
            $adherence,
            $readings30 > 0 ? min(100, (int) round(($readings30 / 30) * 100)) : 0,
            $streak > 0 ? min(100, $streak * 10) : 0,
        ], fn ($v) => $v !== null);
        $engagement = $components ? (int) round(array_sum($components) / count($components)) : 0;

        return [
            'adherence_percent' => $adherence,
            'doses_due_30d' => $due->count(),
            'doses_taken_30d' => $taken->count(),
            'doses_missed_30d' => $due->where('status', 'missed')->count(),
            'readings_7d' => $readings7,
            'readings_30d' => $readings30,
            'logging_streak_days' => $streak,
            'last_reading_at' => $lastReading?->toIso8601String(),
            'days_since_last_reading' => $lastReading
                ? (int) $lastReading->diffInDays($now)
                : null,
            'appointments_kept' => $appointmentsKept,
            'appointments_missed' => $appointmentsMissed,
            'engagement_score' => $engagement,
        ];
    }

    /**
     * Headline numbers for the dossier's stat strip.
     *
     * @param  array<string, mixed>  $dossier
     * @return list<array<string, mixed>>
     */
    private function patientStats(User $user, array $dossier): array
    {
        $clinical = $dossier['clinical'];
        $progress = $dossier['progress'];

        $activeMeds = collect($clinical['medications'])->where('active', true)->count();
        $openAlerts = collect($clinical['alerts'])->where('read', false)->count();

        return [
            [
                'key' => 'engagement',
                'label' => 'Engagement',
                'value' => $progress['engagement_score'].'%',
                'tone' => $this->tone($progress['engagement_score'], 70, 40),
            ],
            [
                'key' => 'adherence',
                'label' => 'Adherence',
                'value' => $progress['adherence_percent'] === null
                    ? '—'
                    : $progress['adherence_percent'].'%',
                'tone' => $progress['adherence_percent'] === null
                    ? 'neutral'
                    : $this->tone($progress['adherence_percent'], 80, 50),
            ],
            [
                'key' => 'readings',
                'label' => 'Readings 30d',
                'value' => (string) $progress['readings_30d'],
                'tone' => $progress['readings_30d'] > 0 ? 'good' : 'warn',
            ],
            [
                'key' => 'medications',
                'label' => 'Active meds',
                'value' => (string) $activeMeds,
                'tone' => 'neutral',
            ],
            [
                'key' => 'alerts',
                'label' => 'Unread alerts',
                'value' => (string) $openAlerts,
                'tone' => $openAlerts > 0 ? 'bad' : 'good',
            ],
            [
                'key' => 'care_team',
                'label' => 'Care team',
                'value' => (string) count($clinical['care_team']),
                'tone' => count($clinical['care_team']) > 0 ? 'good' : 'warn',
            ],
        ];
    }

    // ------------------------------------------------------------------
    // Staff blocks (doctor / assistant / admin)
    // ------------------------------------------------------------------

    /**
     * What this staff member actually does on the platform — the doctor
     * equivalent of a patient's clinical record.
     *
     * @return array<string, mixed>
     */
    private function practice(User $user): array
    {
        $provider = CareProvider::where('user_id', $user->id)->first();

        $caseload = $provider
            ? CareAssignment::with(['patient', 'provider'])
                ->where('provider_id', $provider->id)
                ->whereNull('ended_at')
                ->orderByDesc('assigned_at')
                ->get()
            : collect();

        $pastCaseload = $provider
            ? CareAssignment::where('provider_id', $provider->id)
                ->whereNotNull('ended_at')
                ->count()
            : 0;

        $patientIds = $caseload->pluck('patient_user_id')->all();

        return [
            'provider' => $provider?->toApiArray(),
            'caseload_active' => $caseload->count(),
            'caseload_ended' => $pastCaseload,
            'caseload' => $caseload->map(fn (CareAssignment $a) => [
                'assignment_id' => (string) $a->id,
                'patient_id' => (string) $a->patient_user_id,
                'patient_name' => $a->patient?->fullName(),
                'patient_unique_id' => $a->patient?->unique_id,
                'role' => $a->role,
                'assigned_at' => $a->assigned_at?->toIso8601String(),
                'assigned_reason' => $a->assigned_reason,
            ])->values()->all(),
            'care_requests_handled' => $provider
                ? CareRequest::where(function ($q) use ($provider) {
                    $q->where('provider_id', $provider->id)
                        ->orWhere('assigned_provider_id', $provider->id);
                })->count()
                : 0,
            'care_requests_pending' => $provider
                ? CareRequest::where('provider_id', $provider->id)
                    ->where('status', 'pending')
                    ->count()
                : 0,
            'prescriptions_issued' => Medication::where('prescribed_by_user_id', $user->id)->count(),
            'prescriptions_active' => Medication::where('prescribed_by_user_id', $user->id)
                ->where('active', true)
                ->count(),
            'reports_authored' => ClinicalReport::where('author_user_id', $user->id)->count(),
            'reports_published' => ClinicalReport::where('author_user_id', $user->id)
                ->where('published', true)
                ->count(),
            'meal_plans_assigned' => MealPlan::where('assigned_by_user_id', $user->id)->count(),
            'appointments_total' => Appointment::where('doctor_user_id', $user->id)->count(),
            'appointments_upcoming' => Appointment::where('doctor_user_id', $user->id)
                ->where('scheduled_at', '>=', now())
                ->whereNotIn('status', ['cancelled', 'completed'])
                ->count(),
            'recent_appointments' => Appointment::where('doctor_user_id', $user->id)
                ->orderByDesc('scheduled_at')
                ->limit(20)
                ->get()
                ->map(fn (Appointment $a) => $a->toApiArray() + [
                    'patient_name' => $a->user?->fullName(),
                    'patient_id' => (string) $a->user_id,
                ])
                ->all(),
            'recent_reports' => ClinicalReport::where('author_user_id', $user->id)
                ->orderByDesc('created_at')
                ->limit(20)
                ->get()
                ->map(fn (ClinicalReport $r) => $r->toApiArray() + [
                    'patient_name' => $r->patient?->fullName(),
                ])
                ->all(),
            'patients_alerting' => $patientIds
                ? AppNotification::whereIn('user_id', $patientIds)
                    ->whereIn('kind', ['vital_critical', 'sos'])
                    ->where('read', false)
                    ->count()
                : 0,
        ];
    }

    /**
     * Platform authority — what this account is permitted to do.
     *
     * @return array<string, mixed>
     */
    private function access(User $user): array
    {
        $granted = AssistantPermission::with('grantedBy')
            ->where('user_id', $user->id)
            ->get();

        $keys = $granted->pluck('permission_key')->all();

        return [
            'role' => $user->roleToClient(),
            // Admins hold every key implicitly (see User::hasAssistantPermission).
            'implicit_all' => $user->role === 'admin',
            'granted' => $user->role === 'admin'
                ? AssistantPermission::KEYS
                : $keys,
            'available' => AssistantPermission::KEYS,
            'grants' => $granted->map(fn (AssistantPermission $p) => [
                'key' => $p->permission_key,
                'granted_by_name' => $p->grantedBy?->fullName(),
                'granted_at' => $p->created_at?->toIso8601String(),
            ])->all(),
            'support_tickets_assigned' => SupportTicket::where('assigned_to', $user->id)->count(),
        ];
    }

    /**
     * @param  array<string, mixed>  $dossier
     * @return list<array<string, mixed>>
     */
    private function staffStats(User $user, array $dossier): array
    {
        $practice = $dossier['practice'];
        $access = $dossier['access'];

        if ($user->role === 'doctor') {
            return [
                [
                    'key' => 'caseload',
                    'label' => 'Active patients',
                    'value' => (string) $practice['caseload_active'],
                    'tone' => $practice['caseload_active'] > 0 ? 'good' : 'warn',
                ],
                [
                    'key' => 'alerting',
                    'label' => 'Patients alerting',
                    'value' => (string) $practice['patients_alerting'],
                    'tone' => $practice['patients_alerting'] > 0 ? 'bad' : 'good',
                ],
                [
                    'key' => 'upcoming',
                    'label' => 'Upcoming visits',
                    'value' => (string) $practice['appointments_upcoming'],
                    'tone' => 'neutral',
                ],
                [
                    'key' => 'prescriptions',
                    'label' => 'Active scripts',
                    'value' => (string) $practice['prescriptions_active'],
                    'tone' => 'neutral',
                ],
                [
                    'key' => 'reports',
                    'label' => 'Reports published',
                    'value' => (string) $practice['reports_published'],
                    'tone' => 'neutral',
                ],
                [
                    'key' => 'requests',
                    'label' => 'Pending requests',
                    'value' => (string) $practice['care_requests_pending'],
                    'tone' => $practice['care_requests_pending'] > 0 ? 'warn' : 'good',
                ],
            ];
        }

        return [
            [
                'key' => 'permissions',
                'label' => 'Permissions',
                'value' => (string) count($access['granted']),
                'tone' => count($access['granted']) > 0 ? 'good' : 'warn',
            ],
            [
                'key' => 'tickets',
                'label' => 'Tickets assigned',
                'value' => (string) $access['support_tickets_assigned'],
                'tone' => 'neutral',
            ],
            [
                'key' => 'actions',
                'label' => 'Logged actions',
                'value' => (string) collect($dossier['activity'])->where('is_actor', true)->count(),
                'tone' => 'neutral',
            ],
            [
                'key' => 'sessions',
                'label' => 'Active sessions',
                'value' => (string) $dossier['security']['active_sessions'],
                'tone' => 'neutral',
            ],
        ];
    }

    // ------------------------------------------------------------------
    // helpers
    // ------------------------------------------------------------------

    private function tone(?int $value, int $good, int $warn): string
    {
        if ($value === null) {
            return 'neutral';
        }

        return $value >= $good ? 'good' : ($value >= $warn ? 'warn' : 'bad');
    }

    private function auditTitle(string $action): string
    {
        return match ($action) {
            'user.role_changed' => 'Role changed',
            'user.status_changed' => 'Status changed',
            'user.password_reset' => 'Temporary password issued',
            'user.unlocked' => 'Account unlocked',
            'user.invite_resent' => 'Invite reissued',
            'approval.approved' => 'Application approved',
            'approval.rejected' => 'Application rejected',
            'patient.vitals_assigned' => 'Assigned vitals updated',
            'report.consent_granted' => 'Report consent granted',
            'report.issued' => 'Patient report issued',
            default => ucfirst(str_replace(['.', '_'], ' ', $action)),
        };
    }

    private function initials(string $name): string
    {
        $parts = preg_split('/\s+/', trim($name)) ?: [];
        $parts = array_values(array_filter($parts));
        if ($parts === []) {
            return '?';
        }
        if (count($parts) === 1) {
            return strtoupper(substr($parts[0], 0, 1));
        }

        return strtoupper(substr($parts[0], 0, 1).substr(end($parts), 0, 1));
    }
}
