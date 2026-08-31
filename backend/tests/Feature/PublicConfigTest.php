<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * The app reads this before anyone can sign in, so it must answer without a
 * token — and it must never answer with anything that is not already public.
 */
class PublicConfigTest extends TestCase
{
    use RefreshDatabase;

    public function test_it_serves_the_google_client_id_without_authentication(): void
    {
        config()->set('services.google.client_id', '12345-abc.apps.googleusercontent.com');

        $this->getJson('/api/v1/config')
            ->assertOk()
            ->assertJsonPath('data.google.client_id', '12345-abc.apps.googleusercontent.com')
            ->assertJsonPath('data.google.enabled', true);
    }

    public function test_an_unconfigured_deployment_reports_google_disabled(): void
    {
        config()->set('services.google.client_id', '');

        $this->getJson('/api/v1/config')
            ->assertOk()
            ->assertJsonPath('data.google.enabled', false)
            ->assertJsonPath('data.google.client_id', '');
    }

    public function test_it_never_leaks_the_client_secret(): void
    {
        config()->set('services.google.client_id', '12345-abc.apps.googleusercontent.com');
        config()->set('services.google.client_secret', 'GOCSPX-super-secret-value');

        $body = $this->getJson('/api/v1/config')->assertOk()->getContent();

        // A client ID is published in the page of every site offering Google
        // sign-in. The secret is the whole of the server's identity.
        $this->assertStringNotContainsString('GOCSPX-super-secret-value', $body);
        $this->assertStringNotContainsString('client_secret', $body);
    }

    public function test_apple_uses_the_web_services_id_when_several_audiences_are_allowed(): void
    {
        // APPLE_CLIENT_ID accepts a comma-separated list (web Services ID plus
        // native bundle ID); only the first can drive the web popup.
        config()->set('services.apple.client_id', 'com.mcare.web,com.mcare.ios');

        $this->getJson('/api/v1/config')
            ->assertOk()
            ->assertJsonPath('data.apple.client_id', 'com.mcare.web');
    }

    public function test_the_id_it_publishes_is_the_one_it_verifies_against(): void
    {
        config()->set('services.google.client_id', '99999-xyz.apps.googleusercontent.com');

        $published = $this->getJson('/api/v1/config')
            ->assertOk()
            ->json('data.google.client_id');

        // GoogleIdTokenVerifier rejects any token whose `aud` is not this
        // value, so publishing anything else would hand the app a credential
        // guaranteed to fail.
        $this->assertSame(config('services.google.client_id'), $published);
    }
}
