<?php

namespace App\Events;

use Illuminate\Broadcasting\InteractsWithSockets;
use Illuminate\Broadcasting\PrivateChannel;
use Illuminate\Contracts\Broadcasting\ShouldBroadcastNow;
use Illuminate\Contracts\Events\ShouldDispatchAfterCommit;
use Illuminate\Foundation\Events\Dispatchable;
use Illuminate\Queue\SerializesModels;

/**
 * A compact invalidation signal for authenticated clients.
 *
 * The event intentionally contains no clinical or personal payload. Clients
 * use it only as a prompt to re-hydrate authorised data through the REST API.
 * This keeps Reverb lightweight and preserves one canonical data-mapping path.
 *
 * It broadcasts *now* rather than through the queue. Queued, the signal only
 * left the building if a worker happened to be running, and a deployment
 * without one looked exactly like a deployment with no real-time at all —
 * changes piling up in `jobs` while every client sat on its polling timer.
 * The payload is a few dozen bytes, so the inline publish costs the write
 * that triggered it almost nothing, and [RealtimeSignalService] swallows a
 * failure so an unreachable socket server can never fail a clinical write.
 */
class RealtimeDataChanged implements ShouldBroadcastNow, ShouldDispatchAfterCommit
{
    use Dispatchable, InteractsWithSockets, SerializesModels;

    /** @var list<string> */
    public readonly array $channels;

    /** @var list<string> */
    public readonly array $domains;

    /**
     * @param  list<string>  $channels  Channel names without the `private-` prefix.
     * @param  list<string>  $domains  Changed client data domains.
     */
    public function __construct(
        array $channels,
        array $domains,
        public readonly string $action,
        public readonly string $resourceType,
        public readonly string|int|null $resourceId = null,
    ) {
        $this->channels = array_values(array_unique(array_filter($channels)));
        $this->domains = array_values(array_unique(array_filter($domains)));
    }

    /** @return list<PrivateChannel> */
    public function broadcastOn(): array
    {
        return array_map(
            static fn (string $channel) => new PrivateChannel($channel),
            $this->channels,
        );
    }

    public function broadcastAs(): string
    {
        return 'session.changed';
    }

    /** @return array<string, mixed> */
    public function broadcastWith(): array
    {
        return [
            'domains' => $this->domains,
            'action' => $this->action,
            'resource_type' => $this->resourceType,
            'resource_id' => $this->resourceId === null ? null : (string) $this->resourceId,
            'occurred_at' => now()->toIso8601String(),
        ];
    }
}
