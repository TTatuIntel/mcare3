<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\VitalReportRequest;
use App\Support\ApiResponse;
use Illuminate\Http\Request;

class VitalReportRequestsController extends Controller
{
    use ApiResponse;

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
            'status' => 'pending',
            'current_responder' => 'doctor',
        ]);
        return $this->success(['request' => $req->toApiArray()], 'Report request submitted.', 201);
    }

    public function cancel(Request $request, VitalReportRequest $vitalReportRequest)
    {
        abort_unless($vitalReportRequest->user_id === $request->user()->id, 403);
        $vitalReportRequest->update(['status' => 'cancelled']);
        return $this->success(['request' => $vitalReportRequest->fresh()->toApiArray()], 'Report request cancelled.');
    }
}
