<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\AppNotification;
use App\Support\ApiResponse;
use Illuminate\Http\Request;

class NotificationsController extends Controller
{
    use ApiResponse;

    public function index(Request $request)
    {
        return $this->success([
            'notifications' => $request->user()->appNotifications()
                ->orderByDesc('created_at')
                ->limit(200)
                ->get()
                ->map->toApiArray()
                ->all(),
        ]);
    }

    public function markRead(Request $request, AppNotification $notification)
    {
        abort_unless($notification->user_id === $request->user()->id, 403);
        $notification->update(['read' => true]);
        return $this->success(['notification' => $notification->fresh()->toApiArray()]);
    }

    public function resolve(Request $request, AppNotification $notification)
    {
        abort_unless($notification->user_id === $request->user()->id, 403);
        $notification->update([
            'resolved' => true,
            'resolved_at' => now(),
            'read' => true,
        ]);
        return $this->success(['notification' => $notification->fresh()->toApiArray()]);
    }

    public function markAllRead(Request $request)
    {
        $request->user()->appNotifications()->where('read', false)->update(['read' => true]);
        return $this->success(null, 'All notifications marked read.');
    }
}
