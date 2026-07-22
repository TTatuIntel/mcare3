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
        $query = SosEvent::with('user')->orderByDesc('triggered_at');

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
        ]);

        $admin = $request->user();
        $event->update([
            'status' => $data['status'],
            'responded_by' => $data['responded_by']
                ?? $admin->fullName().' (Admin)',
            'responded_at' => now(),
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
