<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\VitalCatalog;
use App\Services\VitalAlertNotifier;
use App\Support\ApiResponse;
use App\Support\VitalRisk;
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
            'vitals' => $query->limit(1000)->get()->map->toApiArray()->all(),
        ]);
    }

    public function store(Request $request)
    {
        $data = $request->validate([
            'vital_key' => 'required|string',
            'value' => 'required|numeric',
            'secondary_value' => 'nullable|numeric',
            'recorded_at' => 'nullable|date',
            'note' => 'nullable|string',
        ]);

        $range = $request->user()->vitalRangeOverrides()
            ->where('vital_key', $data['vital_key'])
            ->first()
            ?? VitalCatalog::where('vital_key', $data['vital_key'])->first();

        $risk = $range ? VitalRisk::assess((float) $data['value'], $range) : 'unknown';

        $reading = $request->user()->vitalReadings()->create([
            'vital_key' => $data['vital_key'],
            'value' => $data['value'],
            'secondary_value' => $data['secondary_value'] ?? null,
            'recorded_at' => $data['recorded_at'] ?? now(),
            'note' => $data['note'] ?? null,
            'risk' => $risk,
        ]);

        VitalAlertNotifier::notify($request->user(), $reading);

        return $this->success(['vital' => $reading->toApiArray()], 'Reading recorded.', 201);
    }
}
