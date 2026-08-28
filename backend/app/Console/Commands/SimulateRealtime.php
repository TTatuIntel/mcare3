<?php

namespace App\Console\Commands;

use App\Models\AppNotification;
use App\Models\Appointment;
use App\Models\CareAssignment;
use App\Models\ChatMessage;
use App\Models\Conversation;
use App\Models\SosEvent;
use App\Models\User;
use App\Models\VitalCatalog;
use App\Models\VitalReading;
use App\Services\RealtimeSignalService;
use App\Services\SosNotifier;
use App\Services\VitalAlertNotifier;
use App\Support\VitalRisk;
use Illuminate\Console\Command;

/**
 * Creates real, persistent domain events through the same models and notifier
 * services used by the API. Model observers then emit the normal PHI-free
 * Reverb invalidations; this is not a fake frontend timer or fixture overlay.
 */
class SimulateRealtime extends Command
{
    protected $signature = 'mcare:simulate
        {scenario=all : all|vital-critical|sos|message|appointment}
        {--patient=amara.okonkwo@example.com : Active patient email or mCare ID}
        {--json : Emit machine-readable output}
        {--force : Permit execution in production}';

    protected $description = 'Generate real application events for realtime end-to-end testing';

    /** @var list<string> */
    private const SCENARIOS = ['all', 'vital-critical', 'sos', 'message', 'appointment'];

    public function handle(): int
    {
        if (app()->environment('production') && ! $this->option('force')) {
            $this->error('Simulation is disabled in production unless --force is supplied.');

            return self::FAILURE;
        }

        $scenario = (string) $this->argument('scenario');
        if (! in_array($scenario, self::SCENARIOS, true)) {
            $this->error('Unknown scenario. Use: '.implode(', ', self::SCENARIOS));

            return self::INVALID;
        }

        $identifier = (string) $this->option('patient');
        $patient = User::query()
            ->where('role', 'patient')
            ->where('approval_status', 'active')
            ->where(function ($query) use ($identifier): void {
                $query->where('email', $identifier)->orWhere('unique_id', $identifier);
            })
            ->first();

        if (! $patient) {
            $this->error("No active patient found for '{$identifier}'. Run php artisan db:seed first.");

            return self::FAILURE;
        }

        $results = [];
        $selected = $scenario === 'all'
            ? array_values(array_filter(self::SCENARIOS, fn (string $item) => $item !== 'all'))
            : [$scenario];

        foreach ($selected as $item) {
            $results[$item] = match ($item) {
                'vital-critical' => $this->simulateCriticalVital($patient),
                'sos' => $this->simulateSos($patient),
                'message' => $this->simulateMessage($patient),
                'appointment' => $this->simulateAppointment($patient),
            };
        }

        $payload = [
            'patient' => [
                'id' => (string) $patient->id,
                'unique_id' => $patient->unique_id,
                'name' => $patient->fullName(),
            ],
            'scenarios' => $results,
            'realtime' => [
                'broadcast_driver' => config('broadcasting.default'),
                'signals_enabled' => RealtimeSignalService::enabled(),
                'delivery' => 'queued model invalidations plus REST reconciliation',
            ],
        ];

        if ($this->option('json')) {
            $this->line(json_encode($payload, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES));
        } else {
            $this->info('Realtime simulation completed for '.$patient->fullName().'.');
            foreach ($results as $name => $result) {
                $this->line("  {$name}: #{$result['id']} ({$result['status']})");
            }
            $this->newLine();
            $this->line('Run a queue worker and Reverb to observe immediate client updates.');
        }

        return self::SUCCESS;
    }

    /** @return array{id:string,status:string} */
    private function simulateCriticalVital(User $patient): array
    {
        $range = $patient->vitalRangeOverrides()
            ->where('vital_key', 'bloodOxygen')
            ->first()
            ?? VitalCatalog::where('vital_key', 'bloodOxygen')->firstOrFail();
        $value = 84.0;
        $risk = VitalRisk::assess($value, $range);

        $reading = VitalReading::create([
            'user_id' => $patient->id,
            'vital_key' => 'bloodOxygen',
            'value' => $value,
            'secondary_value' => null,
            'risk' => $risk,
            'recorded_at' => now(),
            'note' => 'Realtime simulation: critical oxygen saturation.',
        ]);
        VitalAlertNotifier::notify($patient, $reading);

        return ['id' => (string) $reading->id, 'status' => $risk];
    }

    /** @return array{id:string,status:string} */
    private function simulateSos(User $patient): array
    {
        $event = SosEvent::create([
            'user_id' => $patient->id,
            'kind' => 'medical',
            'status' => 'active',
            'location_label' => 'Realtime simulation · Nairobi test location',
            'latitude' => -1.286389,
            'longitude' => 36.817223,
            'note' => 'Simulation only — exercise acknowledgement and resolution.',
            'triggered_at' => now(),
        ]);
        SosNotifier::onTriggered($event->load('user'));

        return ['id' => (string) $event->id, 'status' => 'active'];
    }

    /** @return array{id:string,status:string} */
    private function simulateMessage(User $patient): array
    {
        $doctor = $this->assignedDoctor($patient);
        if (! $doctor) {
            throw new \RuntimeException('The selected patient has no active doctor assignment.');
        }

        $conversation = Conversation::firstOrCreate(
            ['user_id' => $patient->id, 'participant_user_id' => $doctor->id],
            [
                'participant_name' => 'Dr. '.$doctor->fullName(),
                'participant_role' => 'doctor',
                'participant_specialty' => $doctor->specialty,
            ],
        );
        $message = ChatMessage::create([
            'conversation_id' => $conversation->id,
            'sender_user_id' => $doctor->id,
            'body' => 'Realtime simulation message sent at '.now()->format('H:i:s').'.',
            'read' => false,
            'sent_at' => now(),
        ]);
        AppNotification::create([
            'user_id' => $patient->id,
            'kind' => 'message',
            'title' => 'New message from Dr. '.$doctor->fullName(),
            'body' => $message->body,
            'action_route' => '/patient/messages',
            'action_arguments' => ['conversation_id' => (string) $conversation->id],
            'read' => false,
            'resolved' => false,
        ]);

        return ['id' => (string) $message->id, 'status' => 'unread'];
    }

    /** @return array{id:string,status:string} */
    private function simulateAppointment(User $patient): array
    {
        $doctor = $this->assignedDoctor($patient);
        if (! $doctor) {
            throw new \RuntimeException('The selected patient has no active doctor assignment.');
        }

        $appointment = Appointment::create([
            'user_id' => $patient->id,
            'doctor_user_id' => $doctor->id,
            'doctor_name' => 'Dr. '.$doctor->fullName(),
            'doctor_specialty' => $doctor->specialty,
            'scheduled_at' => now()->addDays(3)->startOfHour(),
            'duration_minutes' => 30,
            'type' => 'virtual',
            'status' => 'confirmed',
            'reason' => 'Realtime simulation appointment',
            'location_or_link' => 'https://meet.mcare.health/simulation-'.$patient->id,
        ]);
        AppNotification::create([
            'user_id' => $patient->id,
            'kind' => 'appointment',
            'title' => 'New appointment confirmed',
            'body' => 'A realtime test appointment was scheduled with Dr. '.$doctor->fullName().'.',
            'action_route' => '/patient/appointments',
            'action_arguments' => ['appointment_id' => (string) $appointment->id],
            'read' => false,
            'resolved' => false,
        ]);

        return ['id' => (string) $appointment->id, 'status' => 'confirmed'];
    }

    private function assignedDoctor(User $patient): ?User
    {
        $assignment = CareAssignment::query()
            ->with('provider.user')
            ->where('patient_user_id', $patient->id)
            ->whereNull('ended_at')
            ->orderByRaw("CASE WHEN role = 'Primary' THEN 0 ELSE 1 END")
            ->first();

        return $assignment?->provider?->user;
    }
}
