<?php

namespace App\Http\Controllers\Api\V1\Admin;

use App\Http\Controllers\Controller;
use App\Models\SystemSetting;
use App\Services\AuditService;
use App\Support\ApiResponse;
use Illuminate\Http\Request;

/**
 * Platform toggles surfaced on the admin System settings screen.
 */
class SystemSettingsController extends Controller
{
    use ApiResponse;

    /** Maps setting keys → UI category labels (Flutter groups by category). */
    private const CATEGORIES = [
        'sms_critical_alerts' => 'Notifications',
        'sms_alerts' => 'Notifications',
        'push_notifications' => 'Notifications',
        'email_digests' => 'Notifications',
        'patient_signup_open' => 'Access',
        'allow_self_registration' => 'Access',
        'two_factor_required' => 'Access',
        'audit_retention' => 'Data',
        'audit_retention_365' => 'Data',
        'maintenance_mode' => 'Runtime',
    ];

    public function __construct(private readonly AuditService $audit) {}

    public function index()
    {
        $settings = SystemSetting::query()
            ->orderBy('key')
            ->get()
            ->map(fn (SystemSetting $s) => $this->toClientArray($s));

        return $this->success(['settings' => $settings]);
    }

    public function update(Request $request, string $key)
    {
        $data = $request->validate([
            'value' => 'required|boolean',
        ]);

        $setting = SystemSetting::query()->where('key', $key)->first();
        if (! $setting) {
            return $this->error('Unknown setting key.', 404);
        }

        $setting->update(['value' => $data['value']]);

        $this->audit->record(
            $request->user(),
            'system.setting_updated',
            $setting->title,
            'security',
            ['key' => $key, 'value' => $data['value']],
        );

        return $this->success(
            ['setting' => $this->toClientArray($setting->fresh())],
            'Setting updated.',
        );
    }

    private function toClientArray(SystemSetting $setting): array
    {
        return [
            'key' => $setting->key,
            'title' => $setting->title,
            'description' => $setting->description,
            'category' => self::CATEGORIES[$setting->key] ?? 'Runtime',
            'value' => (bool) $setting->value,
        ];
    }
}
