<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Resources\AppNotificationResource;
use App\Models\AppNotification;
use App\Services\AlertResolutionNotifier;
use App\Services\RealtimeSignalService;
use App\Support\ApiResponse;
use Illuminate\Http\Request;

class NotificationsController extends Controller
{
    use ApiResponse;

    public function index(Request $request)
    {
        return $this->success([
            'notifications' => AppNotificationResource::collection(
                $request->user()->appNotifications()
                    ->orderByDesc('created_at')
                    ->limit(200)
                    ->get()
            ),
        ]);
    }

    public function markRead(Request $request, AppNotification $notification)
    {
        abort_unless($notification->user_id === $request->user()->id, 403);
        $notification->update(['read' => true]);

        return $this->success(['notification' => new AppNotificationResource($notification->fresh())]);
    }

    public function resolve(Request $request, AppNotification $notification)
    {
        abort_unless($notification->user_id === $request->user()->id, 403);

        // Clinical alerts are closed by the care team, never by the patient
        // they are about. Clearing one is a clinical decision — it records who
        // reviewed the reading and what they did about it (see
        // [AlertResolutionNotifier]) — so a patient dismissing their own
        // critical vital would hide it from the very people meant to act on
        // it. Everything else in the inbox is theirs to clear.
        abort_if(
            in_array($notification->kind, AlertResolutionNotifier::KINDS, true),
            403,
            'Only your care team can clear this alert.',
        );

        $notification->update([
            'resolved' => true,
            'resolved_at' => now(),
            'read' => true,
        ]);

        return $this->success(['notification' => new AppNotificationResource($notification->fresh())]);
    }

    public function markAllRead(Request $request)
    {
        $updated = $request->user()->appNotifications()
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

        return $this->success(null, 'All notifications marked read.');
    }
}
