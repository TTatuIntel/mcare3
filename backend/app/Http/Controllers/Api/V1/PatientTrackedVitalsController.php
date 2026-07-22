<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\VitalCatalog;
use App\Support\ApiResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * Patient-selected optional vitals to show on their dashboard.
 * Assigned vitals (clinician-required) must always remain tracked.
 */
class PatientTrackedVitalsController extends Controller
{
    use ApiResponse;

    public function update(Request $request)
    {
        $user = $request->user();

        $data = $request->validate([
            'tracked_vitals' => 'required|array|min:1',
            'tracked_vitals.*' => 'string',
        ]);

        $assigned = $user->assignedVitals()->pluck('vital_key')->all();
        $enabled = VitalCatalog::where('enabled', true)->pluck('vital_key')->all();

        $keys = collect($data['tracked_vitals'])->unique()->values()->all();

        foreach ($assigned as $key) {
            abort_unless(
                in_array($key, $keys, true),
                422,
                "Assigned vital {$key} must remain tracked."
            );
        }

        foreach ($keys as $key) {
            abort_unless(
                in_array($key, $enabled, true),
                422,
                "Unknown or disabled vital: {$key}"
            );
        }

        DB::transaction(function () use ($user, $keys) {
            $user->trackedVitals()->delete();
            foreach ($keys as $vitalKey) {
                $user->trackedVitals()->create(['vital_key' => $vitalKey]);
            }
        });

        return $this->success([
            'tracked_vitals' => $keys,
        ], 'Tracked vitals updated.');
    }
}
