<?php

namespace Tests\Feature;

use App\Events\RealtimeDataChanged;
use App\Models\AuditEntry;
use App\Models\ExternalAccessToken;
use App\Models\User;
use App\Models\VitalCatalog;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Routing\Middleware\ThrottleRequests;
use Illuminate\Support\Facades\Event;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * README §13 — external access flow coverage.
 * create → resolve-code → write via token → revoke → token is dead.
 * Also validates the §4.1 audit-in-transaction rule (audit rows exist for
 * both create and revoke).
 */
class ExternalAccessLifecycleTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        // The external-write throttle is scoped per token — 30/min — well
        // above what this test needs, but we bypass to keep the test hermetic.
        $this->withoutMiddleware(ThrottleRequests::class);
    }

    public function test_full_lifecycle(): void
    {
        $patient = User::factory()->role('patient')->create();
        Sanctum::actingAs($patient);

        // 1. Patient mints an external-access link.
        $create = $this->postJson('/api/v1/patient/external-access', [
            'label' => 'ER Consult',
            'expires_in_hours' => 24,
        ])->assertCreated();

        $link = $create->json('data.link');
        $this->assertNotEmpty($link['token']);
        $this->assertNotEmpty($link['access_code']);

        // Audit row written inside the same transaction as the create.
        $this->assertDatabaseHas('audit_entries', [
            'actor_user_id' => $patient->id,
            'action' => 'external.link_created',
        ]);

        // 2. External doctor resolves the short code.
        $resolve = $this->postJson('/api/v1/external/resolve-code', [
            'code' => $link['access_code'],
        ])->assertOk();

        $this->assertSame($link['token'], $resolve->json('data.token'));

        // 3. External doctor writes a consultation note via the token.
        $this->postJson("/api/v1/external/{$link['token']}/notes", [
            'note' => 'Patient stable; observing for 4 hours.',
            'doctor_name' => 'Dr. Field',
        ])->assertOk();

        $this->assertDatabaseHas('app_notifications', [
            'user_id' => $patient->id,
            'kind' => 'report',
        ]);

        // 4. Patient revokes.
        $this->patchJson("/api/v1/patient/external-access/{$link['id']}/revoke")
            ->assertOk();

        $this->assertDatabaseHas('audit_entries', [
            'actor_user_id' => $patient->id,
            'action' => 'external.link_revoked',
        ]);

        // 5. Revoked token can no longer write.
        $this->postJson("/api/v1/external/{$link['token']}/notes", [
            'note' => 'This should be rejected.',
        ])->assertStatus(404);
    }

    public function test_max_five_active_links(): void
    {
        $patient = User::factory()->role('patient')->create();
        Sanctum::actingAs($patient);

        // Seed 5 active tokens directly to skip HTTP overhead.
        for ($i = 0; $i < 5; $i++) {
            ExternalAccessToken::create([
                'patient_user_id' => $patient->id,
                'created_by_user_id' => $patient->id,
                'token' => str_repeat('a', 60).$i.'zz',
                'access_code' => 'AAAA-'.str_pad((string) $i, 3, '0', STR_PAD_LEFT).'X',
                'label' => 'preexisting',
                'expires_at' => now()->addDay(),
            ]);
        }

        $this->postJson('/api/v1/patient/external-access', [
            'label' => 'Sixth attempt',
        ])->assertStatus(422);
    }

    public function test_revoke_is_atomic_with_audit(): void
    {
        $patient = User::factory()->role('patient')->create();
        Sanctum::actingAs($patient);

        $token = ExternalAccessToken::create([
            'patient_user_id' => $patient->id,
            'created_by_user_id' => $patient->id,
            'token' => str_repeat('t', 64),
            'access_code' => 'ZZZZ-ZZZZ',
            'label' => 'to-be-revoked',
            'expires_at' => now()->addDay(),
        ]);

        $auditBefore = AuditEntry::where('action', 'external.link_revoked')->count();

        $this->patchJson("/api/v1/patient/external-access/{$token->id}/revoke")
            ->assertOk();

        $this->assertNotNull($token->fresh()->revoked_at);
        $this->assertSame($auditBefore + 1, AuditEntry::where('action', 'external.link_revoked')->count());
    }

    public function test_valid_guest_can_authorize_only_its_private_realtime_channel(): void
    {
        Event::fake([RealtimeDataChanged::class]);

        $patient = User::factory()->role('patient')->create();
        $access = ExternalAccessToken::create([
            'patient_user_id' => $patient->id,
            'created_by_user_id' => $patient->id,
            'token' => str_repeat('r', 64),
            'access_code' => 'LIVE-LINK',
            'label' => 'realtime',
            'expires_at' => now()->addDay(),
        ]);

        config([
            'broadcasting.default' => 'reverb',
            'broadcasting.connections.reverb.key' => 'public-key',
            'broadcasting.connections.reverb.secret' => 'private-secret',
            'broadcasting.connections.reverb.app_id' => 'mcare',
        ]);

        $channel = 'private-external.'.$access->id;
        $portal = $this->getJson("/api/v1/external/{$access->token}")
            ->assertOk()
            ->assertJsonPath('data.realtime_channel', $channel);
        $this->assertNotEmpty($portal->json('data.patient'));

        $expected = 'public-key:'.hash_hmac(
            'sha256',
            '1234.5678:'.$channel,
            'private-secret',
        );
        $this->postJson("/api/v1/external/{$access->token}/broadcasting/auth", [
            'socket_id' => '1234.5678',
            'channel_name' => $channel,
        ])->assertOk()->assertJsonPath('auth', $expected);

        $this->postJson("/api/v1/external/{$access->token}/broadcasting/auth", [
            'socket_id' => '1234.5678',
            'channel_name' => 'private-external.999999',
        ])->assertForbidden();

        $access->update(['revoked_at' => now()]);
        $this->postJson("/api/v1/external/{$access->token}/broadcasting/auth", [
            'socket_id' => '1234.5678',
            'channel_name' => $channel,
        ])->assertNotFound();
    }
}
