<?php

namespace App\Console\Commands;

use App\Models\RequestActivityEvent;
use App\Models\VitalReportRequest;
use Illuminate\Console\Command;

/**
 * Server-side SLA escalation for pending vital report requests.
 *
 * Mirrors the client thresholds (doctor 48h → assistant 24h → admin) so that
 * escalation is authoritative and continues even when no client is running.
 * `current_responder` values use the client role-enum names so the Flutter
 * app maps them directly (`doctor`, `mcareAssistant`, `admin`).
 */
class EscalateVitalReportRequests extends Command
{
    protected $signature = 'vitals:escalate-report-requests';

    protected $description = 'Advance pending vital report requests past their SLA (doctor → assistant → admin).';

    private const DOCTOR_SLA_HOURS = 48;

    private const ASSISTANT_SLA_HOURS = 24;

    public function handle(): int
    {
        $now = now();
        $escalated = 0;

        // Only requests nobody has taken on. `pending` already excludes a
        // claimed request — claiming moves it to `in_progress` — but the
        // `claimed_by` guard says so out loud, because the rule is the point:
        // this clock measures silence, not work in progress, and escalating a
        // report a clinician is mid-way through writing sends an admin to
        // chase someone who is already doing it.
        VitalReportRequest::query()
            ->where('status', VitalReportRequest::PENDING)
            ->whereNull('claimed_by')
            ->orderBy('id')
            ->chunkById(200, function ($requests) use ($now, &$escalated) {
                foreach ($requests as $request) {
                    $anchor = $request->last_escalated_at ?? $request->created_at;
                    if ($anchor === null) {
                        continue;
                    }

                    $elapsedHours = $anchor->diffInHours($now);

                    if ($request->current_responder === 'doctor'
                        && $elapsedHours >= self::DOCTOR_SLA_HOURS) {
                        $request->update([
                            'current_responder' => 'mcareAssistant',
                            'last_escalated_at' => $now,
                        ]);
                        $this->recordEscalation($request, 'mCare assistant');
                        $escalated++;
                        continue;
                    }

                    if ($request->current_responder === 'mcareAssistant'
                        && $elapsedHours >= self::ASSISTANT_SLA_HOURS) {
                        $request->update([
                            'current_responder' => 'admin',
                            'last_escalated_at' => $now,
                        ]);
                        $this->recordEscalation($request, 'care admin');
                        $escalated++;
                    }
                }
            });

        $this->info("Escalated {$escalated} vital report request(s).");

        return self::SUCCESS;
    }

    /**
     * Writes the escalation into the request's own trail.
     *
     * The patient reads that trail. Without this, a request could move two
     * tiers overnight and the timeline would show nothing between "you raised
     * this" and whoever eventually answered — which reads as nobody having
     * looked at it for days, the exact impression escalation exists to avoid.
     */
    private function recordEscalation(VitalReportRequest $request, string $tier): void
    {
        RequestActivityEvent::record(
            $request,
            RequestActivityEvent::ESCALATED,
            'mCare',
            null,
            'No response within the agreed window, so this was passed to '.$tier.'.',
        );
    }
}
