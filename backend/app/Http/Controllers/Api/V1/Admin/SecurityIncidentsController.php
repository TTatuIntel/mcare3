<?php

namespace App\Http\Controllers\Api\V1\Admin;

use App\Http\Controllers\Controller;
use App\Models\AuditEntry;
use App\Models\SosEvent;
use App\Services\SosNotifier;
use App\Support\ApiResponse;
use Illuminate\Http\Request;

/**
 * Aggregated security feed for the assistant / admin Security view.
 * Backed by SOS events + audit_entries where category=security.
 */
class SecurityIncidentsController extends Controller
{
    use ApiResponse;

    public function index(Request $request)
    {
        $resolved = $request->query('resolved');

        $sosQuery = SosEvent::query()->with('user')->orderByDesc('triggered_at');
        if ($resolved === '0' || $resolved === 'false') {
            $sosQuery->whereIn('status', ['active', 'acknowledged']);
        } elseif ($resolved === '1' || $resolved === 'true') {
            $sosQuery->whereIn('status', ['resolved', 'falseAlarm']);
        }

        $canLocation = $request->user()->role === 'admin'
            || $request->user()->hasAssistantPermission('can_access_emergency_location');

        $sosItems = $sosQuery->limit(100)->get()->map(function (SosEvent $e) use ($canLocation) {
            $arr = $e->toApiArray();
            $arr['source'] = 'sos';
            $arr['severity'] = $e->status === 'active' ? 'critical' : 'high';
            $arr['patient_name'] = $e->user?->fullName();
            if (! $canLocation) {
                unset($arr['latitude'], $arr['longitude']);
            }
            return $arr;
        });

        $auditItems = AuditEntry::query()
            ->where('category', 'security')
            ->orderByDesc('happened_at')
            ->limit(100)
            ->get()
            ->map(function (AuditEntry $e) {
                return [
                    'id' => 'audit_'.$e->id,
                    'source' => 'audit',
                    'severity' => 'medium',
                    'action' => $e->action,
                    'actor' => $e->actor_label,
                    'target' => $e->target,
                    'happened_at' => $e->happened_at?->toIso8601String(),
                ];
            });

        $combined = $sosItems->concat($auditItems)
            ->sortByDesc(fn ($i) => $i['happened_at'] ?? $i['triggered_at'] ?? '')
            ->values();

        return $this->success(['incidents' => $combined]);
    }

    public function resolve(Request $request, $id)
    {
        // Audit-sourced rows are immutable — acknowledgement is a no-op.
        if (str_starts_with((string) $id, 'audit_')) {
            return $this->success(['id' => $id], 'Acknowledged.');
        }

        // Numeric ID — SOS-sourced incident; acknowledge the underlying SOS event.
        $event = SosEvent::find((int) $id);
        if (! $event) {
            return $this->error('Incident not found.', 404);
        }

        if (in_array($event->status, ['resolved', 'falseAlarm'], true)) {
            return $this->success(['id' => $id], 'Already resolved.');
        }

        $admin = $request->user();
        $event->update([
            'status'       => 'acknowledged',
            'responded_by' => $admin->fullName().' (Admin)',
            'responded_at' => now(),
        ]);

        SosNotifier::onResolved($event->fresh(), 'acknowledged', $admin);

        AuditEntry::create([
            'actor_user_id' => $admin->id,
            'actor_label'   => $admin->fullName().' (Admin)',
            'action'        => 'Acknowledged security incident',
            'target'        => ($event->user?->fullName() ?? 'Patient').' · SOS acknowledged',
            'category'      => 'security',
            'happened_at'   => now(),
        ]);

        return $this->success(['id' => $id], 'Acknowledged.');
    }
}
