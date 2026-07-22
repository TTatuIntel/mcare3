<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\SosEvent;
use App\Services\SosNotifier;
use App\Support\ApiResponse;
use Illuminate\Http\Request;

class SosController extends Controller
{
    use ApiResponse;

    public function trigger(Request $request)
    {
        $data = $request->validate([
            'kind' => 'required|string|in:medical,accident,fall,panic,other',
            'location_label' => 'nullable|string|max:200',
            'latitude' => 'nullable|numeric|between:-90,90',
            'longitude' => 'nullable|numeric|between:-180,180',
            'note' => 'nullable|string',
        ]);

        $user = $request->user();

        $existing = $user->sosEvents()
            ->whereIn('status', ['active', 'acknowledged'])
            ->first();
        if ($existing) {
            return $this->success(
                ['event' => $existing->toApiArray()],
                'SOS is already active.',
            );
        }

        $event = $user->sosEvents()->create([
            ...$data,
            'status' => 'active',
            'triggered_at' => now(),
        ]);

        SosNotifier::onTriggered($event->load('user'));

        return $this->success(['event' => $event->toApiArray()], 'SOS triggered.', 201);
    }

    public function resolve(Request $request, SosEvent $event)
    {
        abort_unless($event->user_id === $request->user()->id, 403);
        $data = $request->validate([
            'status' => 'required|string|in:acknowledged,resolved,falseAlarm',
            'responded_by' => 'nullable|string|max:120',
        ]);
        $event->update([
            'status' => $data['status'],
            'responded_by' => $data['responded_by'] ?? 'Patient',
            'responded_at' => now(),
        ]);

        SosNotifier::onResolved($event->fresh(), $data['status']);

        return $this->success(['event' => $event->fresh()->toApiArray()], 'SOS updated.');
    }
}
