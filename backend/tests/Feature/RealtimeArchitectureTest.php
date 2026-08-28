<?php

namespace Tests\Feature;

use App\Events\RealtimeDataChanged;
use App\Models\ChatMessage;
use App\Models\SosResponseAction;
use App\Models\User;
use App\Models\UserInvite;
use App\Services\RealtimeSignalService;
use Illuminate\Support\Facades\Route;
use Tests\TestCase;

class RealtimeArchitectureTest extends TestCase
{
    public function test_realtime_signals_require_a_configured_broadcaster(): void
    {
        config(['broadcasting.default' => 'null']);
        $this->assertFalse(RealtimeSignalService::enabled());

        config(['broadcasting.default' => 'ably']);
        $this->assertFalse(RealtimeSignalService::enabled());

        config(['broadcasting.default' => 'redis']);
        $this->assertFalse(RealtimeSignalService::enabled());

        config([
            'broadcasting.default' => 'reverb',
            'broadcasting.connections.reverb.app_id' => 'test-app',
            'broadcasting.connections.reverb.key' => 'test-key',
            'broadcasting.connections.reverb.secret' => 'test-secret',
        ]);
        $this->assertTrue(RealtimeSignalService::enabled());
    }

    public function test_invalidation_event_is_private_deduplicated_and_phi_free(): void
    {
        $event = new RealtimeDataChanged(
            ['user.7', 'staff', 'user.7'],
            ['messages', 'messages'],
            'created',
            'ChatMessage',
            14,
        );

        $this->assertSame(
            ['private-user.7', 'private-staff'],
            array_map(fn ($channel) => $channel->name, $event->broadcastOn()),
        );
        $this->assertSame('session.changed', $event->broadcastAs());

        $payload = $event->broadcastWith();
        $this->assertSame(['messages'], $payload['domains']);
        $this->assertSame('14', $payload['resource_id']);
        $this->assertArrayNotHasKey('body', $payload);
        $this->assertArrayNotHasKey('patient', $payload);
    }

    public function test_broadcast_auth_uses_the_api_sanctum_stack(): void
    {
        $route = collect(Route::getRoutes()->getRoutes())
            ->first(fn ($candidate) => $candidate->uri() === 'broadcasting/auth');

        $this->assertNotNull($route);
        $middleware = $route->gatherMiddleware();
        $this->assertContains('api', $middleware);
        $this->assertContains('auth:sanctum', $middleware);
        $this->assertContains('account.active', $middleware);
        $this->assertContains('throttle:api-general', $middleware);
    }

    public function test_core_live_models_are_observed(): void
    {
        $observed = RealtimeSignalService::observedModels();

        $this->assertContains(User::class, $observed);
        $this->assertContains(ChatMessage::class, $observed);
        $this->assertContains(SosResponseAction::class, $observed);
        $this->assertContains(UserInvite::class, $observed);
        $this->assertGreaterThanOrEqual(30, count($observed));
    }
}
