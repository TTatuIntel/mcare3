<?php

namespace App\Providers;

use App\Observers\RealtimeModelObserver;
use App\Services\RealtimeSignalService;
use Illuminate\Cache\RateLimiting\Limit;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        //
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        $this->registerRateLimiters();

        foreach (RealtimeSignalService::observedModels() as $model) {
            $model::observe(RealtimeModelObserver::class);
        }
    }

    /**
     * Named rate limiters per README v2 §6.5.
     *
     * Applied to routes via `throttle:{name}` — see routes/api.php.
     */
    protected function registerRateLimiters(): void
    {
        // Auth: 5/min/IP AND 5/15min per submitted email pair.
        // Two Limit objects → both must pass.
        RateLimiter::for('auth-login', function (Request $request) {
            $identifier = strtolower(trim((string) $request->input(
                'identifier',
                $request->input('email', ''),
            )));

            return [
                Limit::perMinute(5)->by('ip:'.$request->ip()),
                Limit::perMinutes(15, 5)->by('identity:'.hash('sha256', $identifier)),
            ];
        });

        RateLimiter::for('auth-otp', function (Request $request) {
            $identifier = strtolower(trim((string) $request->input('identifier', '')));

            return [
                Limit::perMinute(6)->by('otp-ip:'.$request->ip()),
                Limit::perMinutes(15, 6)->by('otp-identity:'.hash('sha256', $identifier)),
            ];
        });

        // External code exchange — brute-forceable, keep tight.
        RateLimiter::for('external-resolve', function (Request $request) {
            return Limit::perMinute(6)->by('ip:'.$request->ip());
        });

        // External-doctor writes: scoped per token (path segment), not per IP,
        // so a leaked link can't be used to bulk-write from many IPs.
        RateLimiter::for('external-write', function (Request $request) {
            $token = (string) $request->route('token', '');

            return Limit::perMinute(30)->by('external-token:'.$token);
        });

        // General authenticated API — per-user cap, IP fallback for guests.
        RateLimiter::for('api-general', function (Request $request) {
            $key = $request->user()
                ? 'user:'.$request->user()->getAuthIdentifier()
                : 'ip:'.$request->ip();

            return Limit::perMinute(120)->by($key);
        });

        // Client-fallback polling endpoint (§7.1) — 1/30s/user.
        RateLimiter::for('poll-fallback', function (Request $request) {
            $key = $request->user()
                ? 'user:'.$request->user()->getAuthIdentifier()
                : 'ip:'.$request->ip();

            return Limit::perMinutes(1, 2)->by($key);
        });
    }
}
