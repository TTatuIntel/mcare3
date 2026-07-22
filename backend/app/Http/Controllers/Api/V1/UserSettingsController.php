<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\UserSetting;
use App\Support\ApiResponse;
use Illuminate\Http\Request;

/**
 * Per-user application preferences (theme, language, notification channels,
 * privacy toggles). Available to every authenticated role. Stored as a JSON
 * payload so the shape can evolve with the client without new migrations.
 */
class UserSettingsController extends Controller
{
    use ApiResponse;

    public function show(Request $request)
    {
        $settings = $request->user()->settings;

        return $this->success($settings?->payload, 'Settings loaded.');
    }

    public function update(Request $request)
    {
        $validated = $request->validate([
            'theme_mode' => 'sometimes|nullable|string|in:light,dark,system',
            'language_code' => 'sometimes|nullable|string|max:12',
            'notifications' => 'sometimes|nullable|array',
            'notifications.*' => 'boolean',
            'privacy_share_with_care_team' => 'sometimes|boolean',
            'privacy_allow_external_access' => 'sometimes|boolean',
        ]);

        $setting = UserSetting::firstOrNew(['user_id' => $request->user()->id]);

        // Merge partial updates into the existing payload so a client that
        // sends only the changed key does not wipe the rest.
        $payload = $setting->payload ?? [];
        $setting->payload = array_merge($payload, $validated);
        $setting->save();

        return $this->success($setting->payload, 'Settings saved.');
    }
}
