<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\AppNotification;
use App\Models\VitalReportRequest;
use App\Support\ApiResponse;
use Illuminate\Http\Request;

class DoctorVitalReportRequestsController extends Controller
{
    use ApiResponse;

    public function index(Request $request)
    {
        $patientIds = DoctorAccess::caseloadPatientIds($request->user());
        return $this->success([
            'requests' => VitalReportRequest::whereIn('user_id', $patientIds)
                ->orderByDesc('created_at')
                ->get()
                ->map->toApiArray()
                ->all(),
        ]);
    }

    public function fulfill(Request $request, VitalReportRequest $vitalReportRequest)
    {
        DoctorAccess::assertCaseload($request->user(), $vitalReportRequest->user_id);
        $data = $request->validate([
            'note' => 'nullable|string|max:1000',
        ]);
        $vitalReportRequest->update([
            'status' => 'fulfilled',
            'responded_at' => now(),
            'responded_by' => 'Dr. '.$request->user()->fullName(),
            'response_note' => $data['note'] ?? null,
        ]);
        AppNotification::create([
            'user_id' => $vitalReportRequest->user_id,
            'kind' => 'report',
            'title' => 'Your vital report is ready',
            'body' => 'Dr. '.$request->user()->fullName().' completed your requested report.',
            'action_route' => '/patient/vitals',
            'read' => false,
        ]);
        DoctorAccess::audit(
            $request->user(),
            'Fulfilled vital report request',
            "Request #{$vitalReportRequest->id}"
        );
        return $this->success(['request' => $vitalReportRequest->fresh()->toApiArray()], 'Request fulfilled.');
    }

    public function escalate(Request $request, VitalReportRequest $vitalReportRequest)
    {
        DoctorAccess::assertCaseload($request->user(), $vitalReportRequest->user_id);
        $vitalReportRequest->update([
            'current_responder' => 'admin',
            'last_escalated_at' => now(),
        ]);
        DoctorAccess::audit(
            $request->user(),
            'Escalated vital report request',
            "Request #{$vitalReportRequest->id}"
        );
        return $this->success(['request' => $vitalReportRequest->fresh()->toApiArray()], 'Request escalated.');
    }
}
