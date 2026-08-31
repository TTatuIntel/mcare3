<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Resources\VitalReadingResource;
use App\Models\VitalCatalog;
use App\Services\VitalAlertNotifier;
use App\Support\ApiResponse;
use App\Support\VitalRecorder;
use Illuminate\Http\Request;

class VitalsController extends Controller
{
    use ApiResponse;

    public function index(Request $request)
    {
        $request->validate([
            'vital_key' => 'nullable|string',
            'days' => 'nullable|integer|min:1|max:365',
        ]);
        $query = $request->user()->vitalReadings()
            ->orderByDesc('recorded_at');
        if ($request->filled('vital_key')) {
            $query->where('vital_key', $request->string('vital_key'));
        }
        if ($request->filled('days')) {
            $query->where('recorded_at', '>=', now()->subDays((int) $request->integer('days')));
        }
        return $this->success([
            'vitals' => VitalReadingResource::collection($query->limit(1000)->get()),
        ]);
    }

    public function store(Request $request)
    {
        $data = $request->validate(VitalRecorder::rules());

        // Grading and alerting live in VitalRecorder so a reading logged by
        // staff on the patient's behalf goes through exactly this path.
        $reading = VitalRecorder::record($request->user(), $data);

        return $this->success(['vital' => new VitalReadingResource($reading)], 'Reading recorded.', 201);
    }
}
