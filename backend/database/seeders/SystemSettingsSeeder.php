<?php

namespace Database\Seeders;

use App\Models\SystemSetting;
use Illuminate\Database\Seeder;

class SystemSettingsSeeder extends Seeder
{
    public function run(): void
    {
        $settings = [
            ['key' => 'sms_critical_alerts', 'title' => 'SMS alerts for critical vitals', 'description' => 'Send Twilio SMS for severity ≥ 4.', 'value' => true],
            ['key' => 'push_notifications',  'title' => 'Push notifications',              'description' => 'Firebase Cloud Messaging.',  'value' => true],
            ['key' => 'patient_signup_open', 'title' => 'Allow self-registration (Patients)', 'description' => 'When off, all signups require admin invite.', 'value' => true],
            ['key' => 'audit_retention',     'title' => 'Audit retention 365 days',         'description' => 'Older entries archive to cold storage.', 'value' => true],
            ['key' => 'maintenance_mode',    'title' => 'Maintenance mode',                 'description' => 'Block non-admin sessions for upgrades.', 'value' => false],
        ];

        foreach ($settings as $row) {
            SystemSetting::updateOrCreate(['key' => $row['key']], $row);
        }
    }
}
