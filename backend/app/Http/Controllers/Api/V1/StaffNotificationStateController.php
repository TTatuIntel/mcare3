<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Support\ApiResponse;
use Illuminate\Http\Request;

/**
 * Backward-compatible endpoint for older clients that persisted state for
 * client-computed notifications.
 *
 * Computed staff rows are now ephemeral presentation data. Keeping these
 * response shapes avoids breaking installed clients while deliberately
 * performing no database reads or writes.
 */
class StaffNotificationStateController extends Controller
{
    use ApiResponse;

    public function index(Request $request)
    {
        return $this->success(['states' => []]);
    }

    public function upsert(Request $request)
    {
        $data = $request->validate([
            'key' => 'required|string|max:191',
            'read' => 'sometimes|boolean',
            'resolved' => 'sometimes|boolean',
        ]);

        $resolved = (bool) ($data['resolved'] ?? false);

        return $this->success(['state' => [
            'key' => $data['key'],
            'read' => $resolved || (bool) ($data['read'] ?? false),
            'resolved' => $resolved,
        ]], 'Ephemeral notification state accepted.');
    }

    public function readAll(Request $request)
    {
        $data = $request->validate([
            'keys' => 'required|array',
            'keys.*' => 'string|max:191',
        ]);

        return $this->success(null, 'Notifications marked read.');
    }
}
