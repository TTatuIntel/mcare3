<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\CareAssignment;
use App\Models\CareProvider;
use App\Models\RequestActivityEvent;
use App\Models\VitalReportRequest;
use App\Support\ApiResponse;
use Illuminate\Http\Request;

class VitalReportRequestsController extends Controller
{
    use ApiResponse;

    /**
     * The patient's own requests, with the trail of who has touched each one.
     *
     * The session payload carries these too, but a patient watching a request
     * they just raised needs to see it move without waiting for a full sync —
     * "someone has picked this up" is the whole point of the claim.
     */
    public function index(Request $request)
    {
        $requests = $request->user()->vitalReportRequests()
            ->with('events')
            ->orderByDesc('created_at')
            ->get();

        return $this->success([
            'requests' => $requests->map->toApiArray()->all(),
        ]);
    }

    public function store(Request $request)
    {
        $data = $request->validate([
            'range_from' => 'required|date',
            'range_to' => 'required|date|after_or_equal:range_from',
            'vitals' => 'required|array|min:1',
            'vitals.*' => 'string',
            'note' => 'nullable|string|max:500',
        ]);

        $req = $request->user()->vitalReportRequests()->create([
            ...$data,
            'status' => VitalReportRequest::PENDING,
            'current_responder' => 'doctor',
        ]);

        RequestActivityEvent::record(
            $req,
            RequestActivityEvent::OPENED,
            $request->user()->fullName(),
            $request->user()->id,
            $data['note'] ?? null,
        );

        // Everyone assigned to this patient can act on it, so everyone
        // assigned to this patient is told. A request that only reached one
        // inbox was a shared queue in name only.
        $this->notifyCareTeam($req, $request->user()->fullName());

        return $this->success(
            ['request' => $req->fresh()->load('events')->toApiArray()],
            'Report request sent to your care team.',
            201,
        );
    }

    public function cancel(Request $request, VitalReportRequest $vitalReportRequest)
    {
        abort_unless($vitalReportRequest->user_id === $request->user()->id, 403);

        if (! $vitalReportRequest->isOpen()) {
            return $this->error('This request has already been closed.', 422);
        }

        $vitalReportRequest->update([
            'status' => VitalReportRequest::CANCELLED,
            'claimed_by' => null,
            'claimed_by_name' => null,
            'claimed_at' => null,
            'resolved_at' => now(),
        ]);

        RequestActivityEvent::record(
            $vitalReportRequest,
            RequestActivityEvent::CANCELLED,
            $request->user()->fullName(),
            $request->user()->id,
        );

        return $this->success(
            ['request' => $vitalReportRequest->fresh()->load('events')->toApiArray()],
            'Report request cancelled.',
        );
    }

    /**
     * Alerts every clinician currently assigned to the patient.
     *
     * Never throws: the request is already saved, and a clinician who missed
     * the alert still finds it in the shared queue.
     */
    private function notifyCareTeam(VitalReportRequest $req, string $patientName): void
    {
        try {
            $doctorIds = CareProvider::whereIn(
                'id',
                CareAssignment::where('patient_user_id', $req->user_id)
                    ->whereNull('ended_at')
                    ->pluck('provider_id'),
            )->pluck('user_id')->filter()->unique();

            foreach ($doctorIds as $doctorUserId) {
                \App\Models\AppNotification::create([
                    'user_id' => $doctorUserId,
                    'kind' => 'report',
                    'title' => 'Vital report requested',
                    'body' => $patientName.' asked the care team for a vital report. '
                        .'Open it to take it on.',
                    'action_route' => '/doctor/inbox',
                    'read' => false,
                ]);
            }
        } catch (\Throwable $e) {
            report($e);
        }
    }
}
