<?php

namespace App\Events;

use App\Models\AppNotification;
use App\Models\User;
use App\Models\VitalReading;
use Illuminate\Broadcasting\Channel;
use Illuminate\Broadcasting\InteractsWithSockets;
use Illuminate\Broadcasting\PrivateChannel;
use Illuminate\Contracts\Broadcasting\ShouldBroadcastNow;
use Illuminate\Foundation\Events\Dispatchable;
use Illuminate\Queue\SerializesModels;

/**
 * Rolling-deployment compatibility event for vital alerts.
 *
 * Fires alongside (not instead of) the existing REST-driven update path so
 * the SessionPoller fallback keeps working while the Flutter WS client is
 * Current clients also receive the generic `session.changed` signal. Keeping
 * this event name allows older clients to trigger their REST refresh without
 * sending the clinical reading itself over the socket.
 *
 * An alert is the one signal that must never wait for a queue worker to be
 * running, so it broadcasts inline. [VitalAlertNotifier] absorbs a failure:
 * the alert row is already written and the change buffer already carries it.
 */
class VitalAlertBroadcast implements ShouldBroadcastNow
{
    use Dispatchable, InteractsWithSockets, SerializesModels;

    public function __construct(
        public readonly User $patient,
        public readonly VitalReading $reading,
        public readonly ?AppNotification $notification,
    ) {}

    /**
     * @return array<int, Channel>
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
     * PHI-free invalidation payload. Authorised clients hydrate details through
     * REST, which keeps one canonical mapping and authorization path.
     */
    public function broadcastWith(): array
    {
        return [
            'domains' => ['vitals', 'alerts', 'notifications'],
            'action' => 'created',
            'resource_type' => 'VitalReading',
            'resource_id' => (string) $this->reading->id,
            'occurred_at' => now()->toIso8601String(),
        ];
    }
}
