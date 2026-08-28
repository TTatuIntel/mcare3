<?php

namespace App\Console\Commands;

use App\Models\ExternalAccessToken;
use App\Models\MealPlan;
use App\Models\PatientReportRequest;
use App\Models\SosResponseAction;
use App\Models\User;
use App\Models\UserInvite;
use App\Models\UserSetting;
use App\Models\VitalRangeOverride;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

class DemoDataStatus extends Command
{
    protected $signature = 'mcare:demo-status
        {--json : Emit machine-readable output}
        {--strict : Return a failure code when any required dataset is missing}';

    protected $description = 'Audit the role and workflow coverage of the installed demo dataset';

    public function handle(): int
    {
        $activePatients = User::query()
            ->where('role', 'patient')
            ->where('approval_status', 'active');
        $patientCount = (clone $activePatients)->count();
        $userCount = User::count();

        $checks = [
            $this->minimum('active-admin', User::where('role', 'admin')->where('approval_status', 'active')->count(), 1),
            $this->minimum('active-assistant', User::where('role', 'mcare_assistant')->where('approval_status', 'active')->count(), 1),
            $this->minimum('active-doctors', User::where('role', 'doctor')->where('approval_status', 'active')->count(), 2),
            $this->minimum('active-patients', $patientCount, 5),
            $this->completePatients('health-profiles', $activePatients, 'healthProfile', $patientCount),
            $this->completePatients('emergency-contacts', $activePatients, 'emergencyContacts', $patientCount),
            $this->completePatients('doctor-assignments', $activePatients, 'careAssignments', $patientCount),
            $this->completePatients('vital-readings', $activePatients, 'vitalReadings', $patientCount),
            $this->completePatients('medications', $activePatients, 'medications', $patientCount),
            $this->completePatients('appointments', $activePatients, 'appointments', $patientCount),
            $this->completePatients('documents', $activePatients, 'medicalDocuments', $patientCount),
            $this->completePatients('conversations', $activePatients, 'conversations', $patientCount),
            $this->completePatients('notifications', $activePatients, 'appNotifications', $patientCount),
            $this->completePatients('support-tickets', $activePatients, 'supportTickets', $patientCount),
            $this->completePatients('vital-report-requests', $activePatients, 'vitalReportRequests', $patientCount),
            $this->minimum('meal-plans', MealPlan::distinct('patient_user_id')->count('patient_user_id'), $patientCount),
            $this->minimum('patient-report-lifecycle', PatientReportRequest::count(), $patientCount),
            $this->minimum('external-access', ExternalAccessToken::whereNull('revoked_at')->count(), 1),
            $this->minimum('sos-response-actions', SosResponseAction::count(), 1),
            $this->minimum('vital-range-overrides', VitalRangeOverride::count(), 1),
            $this->minimum('user-settings', UserSetting::count(), $userCount),
            $this->minimum('pending-invitations', UserInvite::count(), 1),
        ];

        $failed = collect($checks)->where('status', 'fail')->count();
        $payload = [
            'ready' => $failed === 0,
            'summary' => [
                'pass' => count($checks) - $failed,
                'fail' => $failed,
            ],
            'checks' => $checks,
            'table_counts' => $this->domainCounts(),
            'intentionally_runtime_only' => [
                'cache',
                'cache_locks',
                'email_verification_codes',
                'failed_jobs',
                'fcm_tokens',
                'job_batches',
                'jobs',
                'password_reset_tokens',
                'personal_access_tokens',
                'sessions',
                'staff_notification_states',
            ],
        ];

        if ($this->option('json')) {
            $this->line(json_encode($payload, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES));
        } else {
            $this->table(
                ['Dataset', 'Status', 'Coverage'],
                collect($checks)->map(fn (array $check) => [
                    $check['dataset'],
                    strtoupper($check['status']),
                    $check['detail'],
                ])->all(),
            );
        }

        return $this->option('strict') && $failed > 0
            ? self::FAILURE
            : self::SUCCESS;
    }

    /** @return array{dataset:string,status:string,detail:string} */
    private function minimum(string $dataset, int $actual, int $minimum): array
    {
        return [
            'dataset' => $dataset,
            'status' => $actual >= $minimum ? 'pass' : 'fail',
            'detail' => "{$actual} present; {$minimum} required",
        ];
    }

    /** @return array{dataset:string,status:string,detail:string} */
    private function completePatients(
        string $dataset,
        $query,
        string $relation,
        int $patientCount,
    ): array {
        $covered = (clone $query)->has($relation)->count();

        return [
            'dataset' => $dataset,
            'status' => $covered === $patientCount && $patientCount > 0 ? 'pass' : 'fail',
            'detail' => "{$covered}/{$patientCount} active patients covered",
        ];
    }

    /** @return array<string, int> */
    private function domainCounts(): array
    {
        $tables = [
            'users', 'patient_health_profiles', 'emergency_contacts',
            'care_providers', 'care_assignments', 'care_requests',
            'vital_readings', 'vital_range_overrides', 'medications',
            'medication_doses', 'appointments', 'meal_plans',
            'medical_documents', 'conversations', 'chat_messages',
            'app_notifications', 'support_tickets', 'support_ticket_replies',
            'sos_events', 'sos_response_actions', 'vital_report_requests',
            'patient_report_requests', 'external_access_tokens', 'user_settings',
            'user_invites', 'announcements', 'audit_entries',
        ];

        return collect($tables)->mapWithKeys(
            fn (string $table) => [$table => DB::table($table)->count()],
        )->all();
    }
}
