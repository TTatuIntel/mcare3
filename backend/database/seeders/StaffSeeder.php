<?php

namespace Database\Seeders;

use App\Models\Announcement;
use App\Models\AppNotification;
use App\Models\AssistantPermission;
use App\Models\CareProvider;
use App\Models\User;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Hash;

class StaffSeeder extends Seeder
{
    public function run(): void
    {
        // ── Admin ──────────────────────────────────────────────────────────
        $admin = User::updateOrCreate(
            ['email' => 'admin@mcare.health'],
            [
                'unique_id'         => 'MCR-AD-0014',
                'first_name'        => 'Nia',
                'last_name'         => 'Chebet',
                'phone'             => '+254 720 111 010',
                'role'              => 'admin',
                'approval_status'   => 'active',
                'password'          => Hash::make('demo-password'),
                'email_verified_at' => now(),
            ],
        );

        // ── mCare Assistant ────────────────────────────────────────────────
        $assistant = User::updateOrCreate(
            ['email' => 'assistant@mcare.health'],
            [
                'unique_id'         => 'MCR-MA-0058',
                'first_name'        => 'Tendai',
                'last_name'         => 'Moyo',
                'phone'             => '+254 720 222 020',
                'role'              => 'mcare_assistant',
                'approval_status'   => 'active',
                'password'          => Hash::make('demo-password'),
                'email_verified_at' => now(),
            ],
        );

        foreach (AssistantPermission::KEYS as $key) {
            AssistantPermission::updateOrCreate(
                ['user_id' => $assistant->id, 'permission_key' => $key],
                ['granted_by_user_id' => $admin->id],
            );
        }

        // ── Active Doctors ─────────────────────────────────────────────────
        $mensah = User::updateOrCreate(
            ['email' => 'dr.mensah@mcare.health'],
            [
                'unique_id'         => 'MCR-DR-0231',
                'first_name'        => 'Kojo',
                'last_name'         => 'Mensah',
                'phone'             => '+254 720 444 100',
                'role'              => 'doctor',
                'approval_status'   => 'active',
                'password'          => Hash::make('demo-password'),
                'email_verified_at' => now(),
            ],
        );

        $adeyemi = User::updateOrCreate(
            ['email' => 'dr.adeyemi@mcare.health'],
            [
                'unique_id'         => 'MCR-DR-0312',
                'first_name'        => 'Sarah',
                'last_name'         => 'Adeyemi',
                'phone'             => '+254 720 444 101',
                'role'              => 'doctor',
                'approval_status'   => 'active',
                'password'          => Hash::make('demo-password'),
                'email_verified_at' => now(),
            ],
        );

        CareProvider::updateOrCreate(
            ['user_id' => $mensah->id],
            [
                'name'             => 'Dr. Kojo Mensah',
                'specialty'        => 'Internal medicine',
                'facility'         => 'Aga Khan Hospital, Nairobi',
                'years_experience' => 12,
                'rating'           => 4.8,
                'total_reviews'    => 240,
                'bio'              => 'Specialises in chronic disease management.',
                'languages'        => ['English', 'Swahili'],
            ],
        );

        CareProvider::updateOrCreate(
            ['user_id' => $adeyemi->id],
            [
                'name'             => 'Dr. Sarah Adeyemi',
                'specialty'        => 'Endocrinology',
                'facility'         => 'Nairobi Hospital',
                'years_experience' => 9,
                'rating'           => 4.7,
                'total_reviews'    => 165,
                'bio'              => 'Diabetes and hormonal disorders.',
                'languages'        => ['English'],
            ],
        );

        // ── Pending Applications ───────────────────────────────────────────
        User::updateOrCreate(
            ['email' => 'dr.kamau@mcare.health'],
            [
                'unique_id'       => 'MCR-DR-PEND1',
                'first_name'      => 'James',
                'last_name'       => 'Kamau',
                'phone'           => '+254 711 222 333',
                'role'            => 'doctor',
                'approval_status' => 'pending_approval',
                'password'        => Hash::make('demo-password'),
            ],
        );

        User::updateOrCreate(
            ['email' => 'dr.wanjiru@mcare.health'],
            [
                'unique_id'       => 'MCR-DR-PEND2',
                'first_name'      => 'Mary',
                'last_name'       => 'Wanjiru',
                'phone'           => '+254 711 444 555',
                'role'            => 'doctor',
                'approval_status' => 'pending_approval',
                'password'        => Hash::make('demo-password'),
            ],
        );

        // ── Announcements ──────────────────────────────────────────────────
        Announcement::updateOrCreate(
            ['title' => 'Welcome to mCare'],
            [
                'body'               => 'Thanks for being part of the launch. Tap the menu to explore your dashboard.',
                'audience'           => 'all',
                'cta_label'          => 'View dashboard',
                'cta_url'            => null,
                'is_published'       => true,
                'starts_at'          => now()->subDay(),
                'created_by_user_id' => $admin->id,
            ],
        );

        Announcement::updateOrCreate(
            ['title' => 'Doctors — new prescriptions tools'],
            [
                'body'               => 'The prescriptions panel now supports refill tracking and revocation. Check the Workspace page.',
                'audience'           => 'doctors',
                'is_published'       => true,
                'starts_at'          => now()->subHours(6),
                'created_by_user_id' => $admin->id,
            ],
        );

        // ── Admin Notifications ────────────────────────────────────────────
        $adminNotifications = [
            [
                'kind'        => 'sos',
                'title'       => 'SOS resolved — Amara Okonkwo',
                'body'        => 'Medical alert in Nairobi, Westlands has been resolved by Admin Team.',
                'read'        => true,
                'resolved'    => true,
                'resolved_at' => now()->subHours(2),
            ],
            [
                'kind'        => 'approval',
                'title'       => '2 new healthworker applications',
                'body'        => 'Dr. James Kamau and Dr. Mary Wanjiru are awaiting approval.',
                'read'        => false,
                'resolved'    => false,
                'resolved_at' => null,
            ],
            [
                'kind'        => 'support',
                'title'       => 'Support ticket opened',
                'body'        => 'Amara Okonkwo — Cannot upload PDF documents.',
                'read'        => false,
                'resolved'    => false,
                'resolved_at' => null,
            ],
        ];

        foreach ($adminNotifications as $n) {
            AppNotification::firstOrCreate(
                ['user_id' => $admin->id, 'title' => $n['title']],
                array_merge($n, ['user_id' => $admin->id]),
            );
        }
    }
}
