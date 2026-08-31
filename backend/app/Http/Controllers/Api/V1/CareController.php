<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\CareAssignment;
use App\Models\CareProvider;
use App\Models\CareRequest;
use App\Support\ApiResponse;
use Illuminate\Http\Request;

class CareController extends Controller
{
    use ApiResponse;

    public function providers()
    {
        return $this->success([
            'providers' => CareProvider::query()
                ->whereHas('user', fn ($query) => $query
                    ->where('role', 'doctor')
                    ->where('approval_status', 'active')
                    ->whereNotNull('email_verified_at'))
                ->orderBy('name')
                ->get()
                ->map->toApiArray()
                ->all(),
        ]);
    }

    public function requestProvider(Request $request)
    {
        $data = $request->validate([
            'provider_id' => 'required|exists:care_providers,id',
            'reason' => 'nullable|string|max:200',
        ]);
        $provider = CareProvider::findOrFail($data['provider_id']);
        if (! $provider->user()
            ->where('role', 'doctor')
            ->where('approval_status', 'active')
            ->whereNotNull('email_verified_at')
            ->exists()) {
            return $this->error('That care provider is not currently available.', 422);
        }
        $user = $request->user();

        // Already on the team — a second request would ask for what the patient
        // already has, and would land on the admin queue as noise.
        $assigned = CareAssignment::query()
            ->where('patient_user_id', $user->id)
            ->where('provider_id', $provider->id)
            ->whereNull('ended_at')
            ->exists();
        if ($assigned) {
            return $this->error($provider->name.' is already on your care team.', 422);
        }

        // One open request per provider. A duplicate tap returns the request the
        // patient already has rather than creating a second one, so a retry on a
        // flaky connection stays safe and the admin queue never doubles up.
        $existing = $user->careRequests()
            ->where('provider_id', $provider->id)
            ->where('status', 'pending')
            ->latest('id')
            ->first();
        if ($existing) {
            return $this->success(
                ['request' => $existing->toApiArray()],
                'You already have a pending request with '.$provider->name.'.',
            );
        }

        $req = $user->careRequests()->create([
            'provider_id' => $provider->id,
            'provider_name' => $provider->name,
            'provider_specialty' => $provider->specialty,
            'reason' => $data['reason'] ?? null,
            'status' => 'pending',
        ]);
        return $this->success(['request' => $req->toApiArray()], 'Care request submitted.', 201);
    }

    public function cancelRequest(Request $request, CareRequest $careRequest)
    {
        abort_unless($careRequest->user_id === $request->user()->id, 403);
        $careRequest->update(['status' => 'cancelled']);
        return $this->success(['request' => $careRequest->fresh()->toApiArray()], 'Care request cancelled.');
    }
}
