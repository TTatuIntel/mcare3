<?php

namespace App\Events;

use App\Models\AppNotification;
use App\Models\User;
use App\Models\VitalReading;
use Illuminate\Broadcasting\InteractsWithSockets;
use Illuminate\Broadcasting\PrivateChannel;
use Illuminate\Contracts\Broadcasting\ShouldBroadcast;
use Illuminate\Foundation\Events\Dispatchable;
use Illuminate\Queue\SerializesModels;

/**
 * README §7.1 primary channel for vital alerts.
 *
 * Fires alongside (not instead of) the existing REST-driven update path so
 * the SessionPoller fallback keeps working while the Flutter WS client is
 * still being built. Once the client subscribes to `private-user.{id}`
 * (patient) and `private-care-team.{patientId}` (care team), latency drops
 * from ≤30s to <2s (§8 target).
 */
class VitalAlertBroadcast implements ShouldBroadcast
{
    use Dispatchable, InteractsWithSockets, SerializesModels;

    public function __construct(
        public readonly User $patient,
        public readonly VitalReading $reading,
        public readonly ?AppNotification $notification,
    ) {}

    /**
     * @return array<int, \Illuminate\Broadcasting\Channel>
     */
    public function broadcastOn(): array
    {
        return [
            new PrivateChannel('user.'.$this->patient->id),
            new PrivateChannel('care-team.'.$this->patient->id),
        ];
    }

    public function broadcastAs(): string
    {
        return 'vital.alert';
    }

    /**
     * Compact payload — clients hydrate details via REST if they need more.
     * Keeps the WS frame small (§8 lightweight budget).
     */
    public function broadcastWith(): array
    {
        return [
            'patient_id' => (string) $this->patient->id,
            'reading' => [
                'id' => (string) $this->reading->id,
                'vital_key' => $this->reading->vital_key,
                'value' => $this->reading->value,
                'secondary_value' => $this->reading->secondary_value,
                'risk' => $this->reading->risk,
                'recorded_at' => $this->reading->recorded_at?->toIso8601String(),
            ],
            'notification_id' => $this->notification ? (string) $this->notification->id : null,
        ];
    }
}
