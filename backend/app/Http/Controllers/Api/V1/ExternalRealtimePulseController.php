<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\ExternalAccessToken;
use App\Models\RealtimeEvent;
use App\Support\ApiResponse;
use Illuminate\Http\Request;

/**
 * Token-scoped change cursor for the external one-patient portal.
 *
 * The URL token is already the portal credential. This endpoint returns only
 * invalidation domain names and a cursor; clinical data is still read through
 * ExternalDoctorController after the token has been revalidated.
 */
class ExternalRealtimePulseController extends Controller
{
    use ApiResponse;

    private const MAX_ROWS = 400;

    public function __invoke(Request $request, string $token)
    {
        $access = ExternalAccessToken::query()->where('token', $token)->first();
        if (! $access || ! $access->isValid()) {
            return $this->error('This access link is invalid or has expired.', 404);
        }

        $since = max(0, (int) $request->query('since', 0));
        $latest = (int) (RealtimeEvent::max('id') ?? 0);

        if ($since <= 0) {
            return $this->success([
                'cursor' => $latest,
                'domains' => [],
                'stale' => false,
            ]);
        }

        $oldest = (int) (RealtimeEvent::min('id') ?? 0);
        $stale = $oldest > 0 && $since < $oldest - 1;
        $rows = RealtimeEvent::query()
            ->where('channel', 'external.'.$access->id)
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

        $cursor = $rows->count() >= self::MAX_ROWS
            ? (int) $rows->last()->id
            : $latest;

        return $this->success([
            'cursor' => $cursor,
            'domains' => array_keys($domains),
            'stale' => $stale,
        ]);
    }
}
