<?php

return [

    /*
    |--------------------------------------------------------------------------
    | mCare web app URL (Flutter frontend)
    | Used in invite emails and deep links.
    |--------------------------------------------------------------------------
    */
    'frontend_url' => rtrim((string) env('FRONTEND_URL', 'http://localhost:8090'), '/'),

    /*
    | API tokens are always finite. A normal sign-in is intentionally short;
    | "remember me" extends the same revocable Sanctum token, it does not
    | create a second password or an unbounded browser session.
    */
    'auth' => [
        'session_token_minutes' => (int) env('MCARE_SESSION_TOKEN_MINUTES', 480),
        'remember_token_minutes' => (int) env('MCARE_REMEMBER_TOKEN_MINUTES', 43200),
        'max_device_sessions' => (int) env('MCARE_MAX_DEVICE_SESSIONS', 10),

        // Account recovery. The emailed link token and the SMS OTP are both
        // single-use and expire on their own clock, independent of sessions.
        'reset_token_minutes' => (int) env('MCARE_RESET_TOKEN_MINUTES', 60),
        'reset_otp_minutes' => (int) env('MCARE_RESET_OTP_MINUTES', 10),
    ],

    /*
    | Clinical documents and staff credentials must use a private disk. The
    | local disk maps to storage/app/private; production may set this to s3.
    */
    'private_disk' => env('MCARE_PRIVATE_DISK', 'local'),

    /*
    | Ceiling on a single uploaded document, in kilobytes. 10 MB refused most
    | of one MRI series and a good half of the scanned multi-page results
    | patients are actually asked to bring in, so the default is 25 MB. PHP's
    | own upload_max_filesize / post_max_size still bound this from below.
    */
    'max_document_upload_kb' => (int) env('MCARE_MAX_DOCUMENT_UPLOAD_KB', 25600),

    /*
    |--------------------------------------------------------------------------
    | Mock social sign-in (local demo only)
    |--------------------------------------------------------------------------
    | The Flutter demo account picker (used on platforms where the real Google
    | / Apple SDK is not wired up) posts an `id_token` beginning with "mock",
    | which the API accepts without verifying anything. That is a full
    | authentication bypass for any account whose email address is known, so it
    | is OFF in production and can never mint a session for a staff account.
    |
    | Explicitly set ALLOW_MOCK_SOCIAL_LOGIN=true only for an isolated patient
    | demo. It is disabled by default in every environment.
    |--------------------------------------------------------------------------
    */
    'allow_mock_social_login' => (bool) env(
        'ALLOW_MOCK_SOCIAL_LOGIN',
        false,
    ),

    /*
    | Synthetic clinical data must never be installed accidentally on a live
    | system. Local/testing environments are allowed automatically; production
    | requires this separate, explicit emergency override.
    */
    'allow_demo_seed' => (bool) env('MCARE_ALLOW_DEMO_SEED', false),

];
