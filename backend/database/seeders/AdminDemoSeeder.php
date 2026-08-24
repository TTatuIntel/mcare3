<?php

namespace Database\Seeders;

use App\Models\AppNotification;
use App\Models\AuditEntry;
use App\Models\CareAssignment;
use App\Models\CareProvider;
use App\Models\CareRequest;
use App\Models\SosEvent;
use App\Models\SupportTicket;
use App\Models\SupportTicketReply;
use App\Models\User;
use Illuminate\Database\Seeder;

/**
 * Fills in the operational data the admin console needs to look "live":
 * a spread of support tickets, fresh audit activity, pending care requests
 * and additional SOS events across all statuses.
 *
 * Runs last so it can reference staff and patients from earlier seeders.
 */
class AdminDemoSeeder extends Seeder
{
    public function run(): void
    {
        $now = now();

        $admin     = User::where('email', 'admin@mcare.health')->first();
        $assistant = User::where('email', 'assistant@mcare.health')->first();
        $mensah    = User::where('email', 'dr.mensah@mcare.health')->first();
        $adeyemi   = User::where('email', 'dr.adeyemi@mcare.health')->first();

        $amara     = User::where('email', 'amara.okonkwo@example.com')->first();
        $brian     = User::where('email', 'brian.otieno@example.com')->first();
        $wangari   = User::where('email', 'wangari.njeri@example.com')->first();
        $daniel    = User::where('email', 'daniel.mwangi@example.com')->first();
        $esther    = User::where('email', 'esther.wambui@example.com')->first();

        // ── Support tickets ──────────────────────────────────────────────
        $this->seedTicket($amara, $admin, [
            'subject'     => 'Cannot upload PDF documents',
            'description' => 'When I choose a PDF from my phone the upload spinner never finishes.',
            'category'    => 'technical',
            'priority'    => 'high',
            'status'      => 'inProgress',
            'assignee'    => $admin?->id,
            'created'     => $now->copy()->subHours(6),
            'updated'     => $now->copy()->subMinutes(20),
            'replies'     => [
                [
                    'author'   => 'Amara Okonkwo',
                    'is_staff' => false,
                    'body'     => 'It keeps failing on any file above ~2 MB.',
                    'sent_at'  => $now->copy()->subHours(6)->addMinutes(2),
                    'user_id'  => $amara?->id,
                ],
                [
                    'author'   => 'Admin Team',
                    'is_staff' => true,
                    'body'     => 'Looking into it now. Can you try a JPG version while we investigate?',
                    'sent_at'  => $now->copy()->subMinutes(20),
                    'user_id'  => $admin?->id,
                ],
            ],
        ], $now);

        $this->seedTicket($brian, $assistant, [
            'subject'     => 'Change registered phone number',
            'description' => 'I got a new SIM. Please update my number to +254 720 555 010.',
            'category'    => 'account',
            'priority'    => 'medium',
            'status'      => 'open',
            'assignee'    => null,
            'created'     => $now->copy()->subHours(2),
            'updated'     => $now->copy()->subHours(2),
            'replies'     => [],
        ], $now);

        $this->seedTicket($esther, $admin, [
            'subject'     => 'Medication reminder came in at 2am',
            'description' => 'My Amlodipine reminder fired at 02:14 last night. It should be at 8am.',
            'category'    => 'clinical',
            'priority'    => 'medium',
            'status'      => 'resolved',
            'assignee'    => $admin?->id,
            'created'     => $now->copy()->subDays(1),
            'updated'     => $now->copy()->subHours(10),
            'replies'     => [
                [
                    'author'   => 'Admin Team',
                    'is_staff' => true,
                    'body'     => 'Fixed — the schedule was in UTC. It now uses your device timezone.',
                    'sent_at'  => $now->copy()->subHours(10),
                    'user_id'  => $admin?->id,
                ],
            ],
        ], $now);

        $this->seedTicket($daniel, null, [
            'subject'     => 'Requesting export of my step counts',
            'description' => 'Can I get a CSV of the step data from the last 30 days for my own records?',
            'category'    => 'data',
            'priority'    => 'low',
            'status'      => 'open',
            'assignee'    => null,
            'created'     => $now->copy()->subMinutes(45),
            'updated'     => $now->copy()->subMinutes(45),
            'replies'     => [],
        ], $now);

        $this->seedTicket($wangari, $adeyemi, [
            'subject'     => 'Blood pressure cuff pairing lost',
            'description' => 'Since the app update yesterday my BP cuff no longer syncs.',
            'category'    => 'device',
            'priority'    => 'high',
            'status'      => 'inProgress',
            'assignee'    => $adeyemi?->id,
            'created'     => $now->copy()->subHours(3),
            'updated'     => $now->copy()->subMinutes(12),
            'replies'     => [
                [
                    'author'   => 'Dr. Sarah Adeyemi',
                    'is_staff' => true,
                    'body'     => 'Sending a technician to re-pair the device tomorrow morning.',
                    'sent_at'  => $now->copy()->subMinutes(12),
                    'user_id'  => $adeyemi?->id,
                ],
            ],
        ], $now);

        // ── Care requests (patient → provider) ───────────────────────────
        // Covers every state the merged admin workspace renders: pending
        // triage, approved as requested, approved after a re-route to a more
        // suitable doctor, and declined with a reason.
        $mensahProvider  = $mensah  ? CareProvider::where('user_id', $mensah->id)->first()  : null;
        $adeyemiProvider = $adeyemi ? CareProvider::where('user_id', $adeyemi->id)->first() : null;

        $this->seedCareRequest($daniel, $mensahProvider, [
            'reason'  => 'Wellness check-up before travel',
            'status'  => 'pending',
            'created' => $now->copy()->subMinutes(35),
        ]);

        $this->seedCareRequest($brian, $adeyemiProvider, [
            'reason'  => 'Second opinion — endocrine referral',
            'status'  => 'pending',
            'created' => $now->copy()->subHours(1),
        ]);

        $this->seedCareRequest($wangari, $adeyemiProvider, [
            'reason'  => 'Ongoing hypertension needs a specialist review',
            'status'  => 'pending',
            'created' => $now->copy()->subHours(5),
        ]);

        // Approved exactly as the patient asked.
        $this->seedCareRequest($esther, $mensahProvider, [
            'reason'   => 'Routine follow-up after discharge',
            'status'   => 'approved',
            'created'  => $now->copy()->subDays(2),
            'assigned' => $mensahProvider,
            'role'     => 'Primary',
            'note'     => 'Doctor confirmed availability for the follow-up.',
            'decider'  => $admin,
            'decided'  => $now->copy()->subDays(2)->addHours(3),
        ]);

        // Approved, but routed to a more suitable doctor — reason required.
        $this->seedCareRequest($amara, $mensahProvider, [
            'reason'   => 'Insulin dose keeps drifting',
            'status'   => 'approved',
            'created'  => $now->copy()->subDays(4),
            'assigned' => $adeyemiProvider,
            'role'     => 'Specialist',
            'note'     => 'Endocrinology is the better fit for insulin titration.',
            'decider'  => $assistant,
            'decided'  => $now->copy()->subDays(4)->addHours(1),
            'assignment_at' => $now->copy()->subDays(4)->addHours(1),
        ]);

        // Declined — the reason is what the patient was notified with.
        $this->seedCareRequest($daniel, $adeyemiProvider, [
            'reason'  => 'Would like to switch to Dr. Adeyemi',
            'status'  => 'cancelled',
            'created' => $now->copy()->subDays(3),
            'note'    => 'Dr. Adeyemi is not accepting new patients this quarter.',
            'decider' => $admin,
            'decided' => $now->copy()->subDays(3)->addHours(2),
        ]);

        // ── Additional SOS events across statuses ────────────────────────
        if ($daniel) {
            SosEvent::updateOrCreate(
                ['user_id' => $daniel->id, 'kind' => 'safety', 'status' => 'falseAlarm'],
                [
                    'location_label' => 'Nairobi CBD',
                    'note'           => 'Accidental trigger while jogging.',
                    'triggered_at'   => $now->copy()->subDays(1)->subHours(4),
                    'responded_by'   => 'Admin Team',
                    'responded_at'   => $now->copy()->subDays(1)->subHours(3),
                ],
            );
        }

        if ($brian) {
            SosEvent::updateOrCreate(
                ['user_id' => $brian->id, 'kind' => 'medical', 'status' => 'acknowledged'],
                [
                    'location_label' => 'Westlands, Nairobi',
                    'note'           => 'Severe asthma attack — inhaler used, awaiting follow-up.',
                    'triggered_at'   => $now->copy()->subMinutes(22),
                    'responded_by'   => 'Dr. Kojo Mensah',
                    'responded_at'   => $now->copy()->subMinutes(15),
                ],
            );
        }

        // ── Fresh audit trail (last 24h of admin activity) ───────────────
        $auditRows = [
            [
                'actor'    => $admin,
                'label'    => 'Nia Chebet',
                'action'   => 'user.suspended',
                'target'   => 'brian.otieno@example.com',
                'category' => 'activity',
                'at'       => $now->copy()->subMinutes(2),
                'meta'     => ['reason' => 'requested by patient'],
            ],
            [
                'actor'    => $admin,
                'label'    => 'Nia Chebet',
                'action'   => 'user.reactivated',
                'target'   => 'brian.otieno@example.com',
                'category' => 'activity',
                'at'       => $now->copy()->subMinutes(1),
                'meta'     => ['reason' => 'issue resolved'],
            ],
            [
                'actor'    => $assistant,
                'label'    => 'Tendai Moyo',
                'action'   => 'care_request.routed',
                'target'   => 'daniel.mwangi@example.com → Dr. Kojo Mensah',
                'category' => 'activity',
                'at'       => $now->copy()->subMinutes(8),
                'meta'     => [],
            ],
            [
                'actor'    => $admin,
                'label'    => 'Nia Chebet',
                'action'   => 'permissions.granted',
                'target'   => 'assistant@mcare.health',
                'category' => 'security',
                'at'       => $now->copy()->subMinutes(15),
                'meta'     => ['permission_key' => 'can_view_security_incidents'],
            ],
            [
                'actor'    => $mensah,
                'label'    => 'Dr. Kojo Mensah',
                'action'   => 'alert.acknowledged',
                'target'   => 'wangari.njeri@example.com',
                'category' => 'activity',
                'at'       => $now->copy()->subMinutes(25),
                'meta'     => ['alert_kind' => 'vital_critical', 'vital' => 'bloodPressure'],
            ],
            [
                'actor'    => $admin,
                'label'    => 'Nia Chebet',
                'action'   => 'system_setting.updated',
                'target'   => 'sms_critical_alerts',
                'category' => 'activity',
                'at'       => $now->copy()->subHours(1),
                'meta'     => ['from' => false, 'to' => true],
            ],
            [
                'actor'    => null,
                'label'    => 'System',
                'action'   => 'sos.triggered',
                'target'   => 'wangari.njeri@example.com',
                'category' => 'sos',
                'at'       => $now->copy()->subMinutes(8),
                'meta'     => ['kind' => 'medical', 'location' => 'Karen, Nairobi'],
            ],
            [
                'actor'    => $admin,
                'label'    => 'Nia Chebet',
                'action'   => 'announcement.published',
                'target'   => 'Welcome to mCare',
                'category' => 'activity',
                'at'       => $now->copy()->subHours(3),
                'meta'     => ['audience' => 'all'],
            ],
            [
                'actor'    => $adeyemi,
                'label'    => 'Dr. Sarah Adeyemi',
                'action'   => 'support_ticket.assigned',
                'target'   => 'Blood pressure cuff pairing lost',
                'category' => 'activity',
                'at'       => $now->copy()->subMinutes(12),
                'meta'     => [],
            ],
            [
                'actor'    => null,
                'label'    => 'System',
                'action'   => 'auth.locked_out',
                'target'   => 'brian.otieno@example.com',
                'category' => 'security',
                'at'       => $now->copy()->subHours(4),
                'meta'     => ['failed_attempts' => 5, 'ip' => '196.201.214.44'],
            ],
        ];

        foreach ($auditRows as $row) {
            AuditEntry::updateOrCreate(
                [
                    'actor_label' => $row['label'],
                    'action'      => $row['action'],
                    'target'      => $row['target'],
                ],
                [
                    'actor_user_id' => $row['actor']?->id,
                    'category'      => $row['category'],
                    'meta'          => $row['meta'],
                    'happened_at'   => $row['at'],
                ],
            );
        }

        // ── Admin inbox notifications tied to the fresh events ───────────
        if ($admin) {
            AppNotification::updateOrCreate(
                ['user_id' => $admin->id, 'title' => 'New care request — Daniel Mwangi'],
                [
                    'kind'       => 'careRequest',
                    'body'       => 'Wellness check-up before travel — awaiting routing.',
                    'read'       => false,
                    'resolved'   => false,
                    'created_at' => $now->copy()->subMinutes(35),
                    'updated_at' => $now->copy()->subMinutes(35),
                ],
            );

            AppNotification::updateOrCreate(
                ['user_id' => $admin->id, 'title' => 'Support ticket — Amara Okonkwo'],
                [
                    'kind'       => 'support',
                    'body'       => 'PDF upload failing on files above 2 MB.',
                    'read'       => false,
                    'resolved'   => false,
                    'created_at' => $now->copy()->subHours(6),
                    'updated_at' => $now->copy()->subMinutes(20),
                ],
            );
        }
    }

    /**
     * Idempotent care-request upsert, keyed on (patient, provider, reason).
     *
     * A decided request also gets its decision trail — and, when approved, the
     * care assignment that approval would have created, so the seeded data
     * obeys the same "approve ⇒ assigned" rule the API enforces.
     */
    private function seedCareRequest(
        ?User $patient,
        ?CareProvider $requested,
        array $spec,
    ): void {
        if (! $patient || ! $requested) return;

        $assigned = $spec['assigned'] ?? null;

        CareRequest::updateOrCreate(
            [
                'user_id' => $patient->id,
                'provider_id' => $requested->id,
                'reason' => $spec['reason'],
            ],
            [
                'provider_name' => $requested->name,
                'provider_specialty' => $requested->specialty,
                'status' => $spec['status'],
                'assigned_provider_id' => $assigned?->id,
                'assignment_role' => $assigned ? ($spec['role'] ?? 'Primary') : null,
                'decision_note' => $spec['note'] ?? null,
                'decided_by' => ($spec['decider'] ?? null)?->id,
                'decided_at' => $spec['decided'] ?? null,
                'created_at' => $spec['created'],
                'updated_at' => $spec['decided'] ?? $spec['created'],
            ],
        );

        if ($assigned === null) return;

        CareAssignment::updateOrCreate(
            [
                'patient_user_id' => $patient->id,
                'provider_id' => $assigned->id,
                'ended_at' => null,
            ],
            [
                'role' => $spec['role'] ?? 'Primary',
                'assigned_reason' => $spec['note'] ?? null,
                'assigned_by' => ($spec['decider'] ?? null)?->id,
                'assigned_at' => $spec['assignment_at'] ?? $spec['decided'] ?? $spec['created'],
            ],
        );
    }

    /**
     * Idempotent ticket + replies upsert.
     * Uses (user_id, subject) as the identity key.
     */
    private function seedTicket(?User $user, ?User $staff, array $spec, \Carbon\Carbon $now): void
    {
        if (! $user) return;

        $ticket = SupportTicket::updateOrCreate(
            ['user_id' => $user->id, 'subject' => $spec['subject']],
            [
                'description'    => $spec['description'],
                'category'       => $spec['category'],
                'priority'       => $spec['priority'],
                'status'         => $spec['status'],
                'assigned_to'    => $spec['assignee'],
                'updated_at_app' => $spec['updated'],
                'created_at'     => $spec['created'],
                'updated_at'     => $spec['updated'],
            ],
        );

        foreach ($spec['replies'] as $reply) {
            SupportTicketReply::updateOrCreate(
                ['ticket_id' => $ticket->id, 'body' => $reply['body']],
                [
                    'author_user_id' => $reply['user_id'] ?? null,
                    'author'         => $reply['author'],
                    'is_staff'       => $reply['is_staff'],
                    'sent_at'        => $reply['sent_at'],
                ],
            );
        }
    }
}
