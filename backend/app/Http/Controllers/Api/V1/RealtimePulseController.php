<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\RealtimeEvent;
use App\Services\RealtimeSignalService;
use App\Support\ApiResponse;
use Illuminate\Http\Request;

/**
 * "Has anything I can see changed since id N?" — answered in one indexed read.
 *
 * This is the floor under real-time delivery. The socket is faster and is
 * always preferred, but it depends on a Reverb server being up and reachable
 * from the client's network, and neither is guaranteed. Without this, the
 * only fallback was re-fetching an entire role session on a 30-second timer,
 * which is slow, expensive, and the reason updates felt like they needed a
 * manual refresh.
 *
 * The response is a cursor and a list of changed *domain names*. No clinical
 * content crosses this endpoint — the client re-reads the authorised REST
 * endpoints for the domains it was told about, so authorization stays in
 * exactly one place.
 */
class RealtimePulseController extends Controller
{
    use ApiResponse;

    /** Most rows read in one answer; beyond this the client is told to catch up. */
    private const MAX_ROWS = 400;

    public function __invoke(Request $request)
    {
        $user = $request->user();
        $channels = RealtimeSignalService::channelsForUser($user);
        $since = max(0, (int) $request->query('since', 0));

        $latest = (int) (RealtimeEvent::max('id') ?? 0);

        // A client with no cursor is starting up. It has just loaded its data
        // through REST, so it wants a baseline to watch from, not a replay of
        // everything that happened before it arrived.
        if ($since <= 0) {
            return $this->success([
                'cursor' => $latest,
                'domains' => [],
                'stale' => false,
                'retention_minutes' => RealtimeEvent::RETENTION_MINUTES,
                'server_time' => now()->toIso8601String(),
            ]);
        }

        // If the buffer no longer reaches back to where this client left off,
        // some changes were pruned before it asked. Say so plainly rather than
        // reporting a clean "nothing changed" over a gap.
        $oldest = (int) (RealtimeEvent::min('id') ?? 0);
        $stale = $oldest > 0 && $since < $oldest - 1;

        $rows = RealtimeEvent::query()
            ->whereIn('channel', $channels)
            ->where('id', '>', $since)
            ->orderBy('id')
            ->limit(self::MAX_ROWS)
            ->get(['id', 'domains']);

        $domains = [];
        foreach ($rows as $row) {
            foreach ($row->domainList() as $domain) {
                $domains[$domain] = true;
            }
        }

        // A truncated read must not skip what it did not return: advance only
        // as far as the last row actually seen.
        $cursor = $rows->count() >= self::MAX_ROWS
            ? (int) $rows->last()->id
            : $latest;

        return $this->success([
            'cursor' => $cursor,
            'domains' => array_keys($domains),
            'stale' => $stale,
            'retention_minutes' => RealtimeEvent::RETENTION_MINUTES,
            'server_time' => now()->toIso8601String(),
        ]);
    }
}
