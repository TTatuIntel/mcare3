<?php

use Illuminate\Foundation\Inspiring;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Schedule;

Artisan::command('inspire', function () {
    $this->comment(Inspiring::quote());
})->purpose('Display an inspiring quote');

// Authoritative, server-side SLA escalation for vital report requests.
// Runs hourly; the client also escalates locally for immediate UI feedback.
Schedule::command('vitals:escalate-report-requests')->hourly();
