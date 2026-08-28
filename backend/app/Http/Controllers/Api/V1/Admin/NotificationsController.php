<?php

namespace App\Http\Controllers\Api\V1\Admin;

use App\Http\Controllers\Controller;
use App\Models\AppNotification;
use App\Services\RealtimeSignalService;
use App\Support\ApiResponse;
use Illuminate\Http\Request;

class NotificationsController extends Controller
{
    use ApiResponse;

    public function index(Request $request)
    {
        $items = AppNotification::query()
            ->where('user_id', $request->user()->id)
            ->orderByDesc('created_at')
            ->limit(200)
            ->get()
            ->map(fn (AppNotification $n) => $n->toApiArray());

        return $this->success(['notifications' => $items]);
    }

    public function markRead(Request $request, AppNotification $notification)
    {
        $this->ensureOwner($request, $notification);
        $notification->update(['read' => true]);

        return $this->success(['notification' => $notification->fresh()->toApiArray()], 'Marked read.');
    }

    public function resolve(Request $request, AppNotification $notification)
    {
        $this->ensureOwner($request, $notification);
        $notification->update([
            'resolved' => true,
            'resolved_at' => now(),
            'read' => true,
        ]);

        return $this->success(['notification' => $notification->fresh()->toApiArray()], 'Resolved.');
    }

    public function markAllRead(Request $request)
    {
        $updated = AppNotification::query()
            ->where('user_id', $request->user()->id)
            ->where('read', false)
            ->update(['read' => true]);
        if ($updated > 0) {
            RealtimeSignalService::signal(
                ['user.'.$request->user()->id],
                ['notifications', 'alerts'],
                'updated',
                'AppNotification',
            );
        }

        return $this->success(null, 'All marked read.');
    }

    private function ensureOwner(Request $request, AppNotification $notification): void
    {
        if ($notification->user_id !== $request->user()->id && $request->user()->role !== 'admin') {
            abort(response()->json([
                'success' => false,
                'message' => 'Not your notification.',
                'data' => null,
            ], 403));
        }
    }
}
