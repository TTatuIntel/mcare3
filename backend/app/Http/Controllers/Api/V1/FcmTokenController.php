<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\FcmToken;
use App\Support\ApiResponse;
use Illuminate\Http\Request;

class FcmTokenController extends Controller
{
    use ApiResponse;

    public function store(Request $request)
    {
        $data = $request->validate([
            'token' => 'required|string|max:512',
            'platform' => 'nullable|string|in:android,ios,web',
        ]);
        FcmToken::updateOrCreate(
            ['token' => $data['token']],
            [
                'user_id' => $request->user()->id,
                'platform' => $data['platform'] ?? null,
                'last_seen_at' => now(),
            ],
        );
        return $this->success(null, 'FCM token registered.');
    }

    public function destroy(Request $request)
    {
        $data = $request->validate(['token' => 'required|string']);
        FcmToken::where('token', $data['token'])
            ->where('user_id', $request->user()->id)
            ->delete();
        return $this->success(null, 'FCM token cleared.');
    }
}
