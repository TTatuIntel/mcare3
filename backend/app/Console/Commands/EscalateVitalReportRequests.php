<?php

namespace App\Console\Commands;

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

        VitalReportRequest::query()
            ->where('status', 'pending')
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
                        $escalated++;
                        continue;
                    }

                    if ($request->current_responder === 'mcareAssistant'
                        && $elapsedHours >= self::ASSISTANT_SLA_HOURS) {
                        $request->update([
                            'current_responder' => 'admin',
                            'last_escalated_at' => $now,
                        ]);
                        $escalated++;
                    }
                }
            });

        $this->info("Escalated {$escalated} vital report request(s).");

        return self::SUCCESS;
    }
}
