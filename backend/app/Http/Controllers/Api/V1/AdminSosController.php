<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\AuditEntry;
use App\Models\SosEvent;
use App\Services\SosNotifier;
use App\Support\ApiResponse;
use Illuminate\Http\Request;

class AdminSosController extends Controller
{
    use ApiResponse;

    public function index(Request $request)
    {
        $status = $request->query('status', 'active');
        $query = SosEvent::with(['user', 'responseActions.user'])
            ->orderByDesc('triggered_at');

        if ($status === 'active') {
            $query->whereIn('status', ['active', 'acknowledged']);
        } elseif ($status !== 'all') {
            $query->where('status', $status);
        }

        $events = $query->limit(200)->get()->map(function (SosEvent $e) {
            $arr = $e->toApiArray();
            $arr['patient_id'] = (string) $e->user_id;
            $arr['patient_name'] = $e->user?->fullName() ?? '';
            return $arr;
        });

        return $this->success(['sos_events' => $events]);
    }

    public function resolve(Request $request, SosEvent $event)
    {
        $data = $request->validate([
            'status' => 'required|string|in:acknowledged,resolved,falseAlarm',
            'responded_by' => 'nullable|string|max:120',
            'resolution' => 'nullable|string|in:'.implode(',', SosEvent::RESOLUTIONS),
            // Picking "other" means the list did not fit, so the responder
            // has to say what did. Anything else may still carry detail.
            'resolution_note' => 'required_if:resolution,other|nullable|string|max:400',
        ]);

        $admin = $request->user();
        $event->update([
            'status' => $data['status'],
            'responded_by' => $data['responded_by']
                ?? $admin->fullName().' (Admin)',
            'responded_at' => now(),
            // Only a closing status carries an outcome; acknowledging is not
            // an ending and must not stamp one.
            'resolution' => $data['status'] === 'acknowledged'
                ? null
                : ($data['status'] === 'falseAlarm'
                    ? 'other'
                    : ($data['resolution'] ?? null)),
            'resolution_note' => $data['status'] === 'acknowledged'
                ? null
                : ($data['resolution_note'] ?? null),
        ]);

        SosNotifier::onResolved($event->fresh(), $data['status'], $admin);

        AuditEntry::create([
            'actor_user_id' => $admin->id,
            'actor_label' => $admin->fullName().' (Admin)',
            'action' => 'Resolved SOS',
            'target' => ($event->user?->fullName() ?? 'Patient').' · '.$data['status'],
            'category' => 'sos',
            'happened_at' => now(),
        ]);

        return $this->success(
            ['event' => $event->fresh()->toApiArray()],
            'SOS updated.'
        );
    }
}
