<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\RealtimeEvent;
use App\Support\ApiResponse;
use App\Support\RealtimeEndpoint;
use Illuminate\Http\Request;

/**
 * The public, client-side half of this deployment's configuration.
 *
 * OAuth client IDs are compile-time values in the Flutter app, so any build
 * launched without the right `--dart-define` ships an app that reports social
 * sign-in as unconfigured — and any build launched with the *wrong* one gets
 * its tokens rejected here as an audience mismatch. Both failures are silent
 * until a user taps the button.
 *
 * Serving them from the API that verifies the tokens removes the whole class:
 * the app cannot disagree with the server about the server's own client ID,
 * and a corrected credential takes effect on reload rather than on rebuild.
 *
 * Only values that are already public may appear here. An OAuth client ID is
 * published in the page of every site that offers Google sign-in; the client
 * *secret* is not, and never leaves the backend. The same rule admits the
 * real-time block: a Reverb app key is public by design, its secret is not.
 */
class PublicConfigController extends Controller
{
    use ApiResponse;

    public function __invoke(Request $request)
    {
        $google = (string) config('services.google.client_id', '');
        $apple = (string) config('services.apple.client_id', '');

        // Comma-separated audiences are allowed for Apple (web Services ID
        // plus native bundle ID). The web flow can only use one, and the first
        // is the Services ID by convention.
        $appleWeb = trim(explode(',', $apple)[0] ?? '');

        return $this->success([
            'google' => [
                'client_id' => $google,
                'enabled' => $google !== '',
            ],
            'apple' => [
                'client_id' => $appleWeb,
                'redirect_uri' => (string) config('mcare.frontend_url', ''),
                'enabled' => $appleWeb !== '',
            ],
            // How to receive changes as they happen. `socket` is the fast
            // path when this deployment runs one; `pulse` is the floor that
            // works everywhere, and the app uses it whenever the socket is
            // not currently carrying events.
            'realtime' => [
                'socket' => RealtimeEndpoint::describe($request),
                'pulse' => [
                    'path' => '/me/pulse',
                    'interval_ms' => 3000,
                    'retention_minutes' => RealtimeEvent::RETENTION_MINUTES,
                ],
            ],
        ], 'Public client configuration.');
    }
}
