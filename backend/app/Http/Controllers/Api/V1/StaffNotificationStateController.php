<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\StaffNotificationState;
use App\Support\ApiResponse;
use Illuminate\Http\Request;

/**
 * Read/resolve state for client-computed staff notifications. Available to any
 * authenticated user; the keys are opaque strings owned by the client.
 */
class StaffNotificationStateController extends Controller
{
    use ApiResponse;

    public function index(Request $request)
    {
        return $this->success([
            'states' => $request->user()->staffNotificationStates()
                ->get()
                ->map->toApiArray()
                ->all(),
        ]);
    }

    public function upsert(Request $request)
    {
        $data = $request->validate([
            'key' => 'required|string|max:191',
            'read' => 'sometimes|boolean',
            'resolved' => 'sometimes|boolean',
        ]);

        $state = StaffNotificationState::firstOrNew([
            'user_id' => $request->user()->id,
            'notification_key' => $data['key'],
        ]);

        if (array_key_exists('read', $data)) {
            $state->read_at = $data['read'] ? ($state->read_at ?? now()) : null;
        }
        if (array_key_exists('resolved', $data)) {
            $state->resolved_at = $data['resolved'] ? ($state->resolved_at ?? now()) : null;
            // Resolving implies read.
            if ($data['resolved']) {
                $state->read_at = $state->read_at ?? now();
            }
        }
        $state->save();

        return $this->success(['state' => $state->toApiArray()], 'Notification state saved.');
    }

    public function readAll(Request $request)
    {
        $data = $request->validate([
            'keys' => 'required|array',
            'keys.*' => 'string|max:191',
        ]);

        foreach ($data['keys'] as $key) {
            $state = StaffNotificationState::firstOrNew([
                'user_id' => $request->user()->id,
                'notification_key' => $key,
            ]);
            $state->read_at = $state->read_at ?? now();
            $state->save();
        }

        return $this->success(null, 'Notifications marked read.');
    }
}
