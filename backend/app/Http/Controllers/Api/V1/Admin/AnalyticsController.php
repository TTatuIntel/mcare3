<?php

namespace App\Http\Controllers\Api\V1\Admin;

use App\Http\Controllers\Controller;
use App\Models\AppNotification;
use App\Models\Appointment;
use App\Models\AuditEntry;
use App\Models\CareRequest;
use App\Models\SosEvent;
use App\Models\SupportTicket;
use App\Models\User;
use App\Models\VitalReading;
use App\Support\ApiResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class AnalyticsController extends Controller
{
    use ApiResponse;

    public function kpis()
    {
        $activePatients = User::where('role', 'patient')
            ->where('approval_status', 'active')
            ->count();
        $patientsWeekAgo = User::where('role', 'patient')
            ->where('approval_status', 'active')
            ->where('created_at', '<=', now()->subWeek())
            ->count();

        $openAlerts = AppNotification::whereIn('kind', ['vital_warning', 'vital_critical', 'sos'])
            ->where('resolved', false)
            ->where('read', false)
            ->count();
        $openAlertsYesterday = AppNotification::whereIn('kind', ['vital_warning', 'vital_critical', 'sos'])
            ->where('resolved', false)
            ->where('read', false)
            ->where('created_at', '<', now()->startOfDay())
            ->count();

        $avgResponseSeconds = $this->averageAlertAckSeconds();
        $avgResponseYesterday = $this->averageAlertAckSeconds(now()->subDay()->startOfDay(), now()->startOfDay());

        $kpis = [
            // Legacy keys kept for backward compatibility.
            'patients' => $activePatients,
            'doctors' => User::where('role', 'doctor')->count(),
            'assistants' => User::where('role', 'mcare_assistant')->count(),
            'pending_approvals' => User::whereIn('role', ['doctor', 'mcare_assistant'])
                ->where('approval_status', 'pending_approval')->count(),
            'open_care_requests' => CareRequest::where('status', 'pending')->count(),
            'open_tickets' => SupportTicket::whereIn('status', ['open', 'inProgress'])->count(),
            'active_sos' => SosEvent::whereIn('status', ['active', 'acknowledged'])->count(),
            'audit_today' => AuditEntry::whereDate('happened_at', today())->count(),
            // Frontend analytics/dashboard keys.
            'active_patients' => $activePatients,
            'active_patients_delta' => $this->percentDelta($activePatients, $patientsWeekAgo),
            'open_alerts' => $openAlerts,
            'open_alerts_delta' => $this->percentDelta($openAlerts, $openAlertsYesterday),
            'avg_response_seconds' => $avgResponseSeconds,
            'avg_response_delta' => $this->percentDelta(
                $avgResponseSeconds ?? 0,
                $avgResponseYesterday ?? 0,
            ),
        ];

        return $this->success(['kpis' => $kpis]);
    }

    private function percentDelta(int|float $current, int|float $previous): float
    {
        if ($previous == 0) {
            return $current > 0 ? 100.0 : 0.0;
        }

        return round((($current - $previous) / $previous) * 100, 1);
    }

    private function averageAlertAckSeconds(?\DateTimeInterface $from = null, ?\DateTimeInterface $to = null): ?int
    {
        $query = AppNotification::whereIn('kind', ['vital_warning', 'vital_critical'])
            ->where('read', true);

        if ($from !== null && $to !== null) {
            $query->whereBetween('updated_at', [$from, $to]);
        }

        $rows = $query->limit(500)->get(['created_at', 'updated_at']);
        if ($rows->isEmpty()) {
            return null;
        }

        $total = $rows->sum(fn (AppNotification $n) => max(
            0,
            $n->updated_at?->diffInSeconds($n->created_at) ?? 0
        ));

        return (int) round($total / $rows->count());
    }

    public function timeseries(Request $request)
    {
        $metric = $request->query('metric', 'signups');
        $from = $request->query('from', now()->subDays(30)->startOfDay()->toDateTimeString());
        $to   = $request->query('to',   now()->endOfDay()->toDateTimeString());

        $rows = match ($metric) {
            'signups', 'registrations' => User::query()
                ->whereBetween('created_at', [$from, $to])
                ->select(DB::raw('DATE(created_at) as day'), DB::raw('COUNT(*) as value'))
                ->groupBy('day')->orderBy('day')->get(),
            'sos' => SosEvent::query()
                ->whereBetween('triggered_at', [$from, $to])
                ->select(DB::raw('DATE(triggered_at) as day'), DB::raw('COUNT(*) as value'))
                ->groupBy('day')->orderBy('day')->get(),
            'tickets' => SupportTicket::query()
                ->whereBetween('created_at', [$from, $to])
                ->select(DB::raw('DATE(created_at) as day'), DB::raw('COUNT(*) as value'))
                ->groupBy('day')->orderBy('day')->get(),
            'vitals' => VitalReading::query()
                ->whereBetween('recorded_at', [$from, $to])
                ->select(DB::raw('DATE(recorded_at) as day'), DB::raw('COUNT(*) as value'))
                ->groupBy('day')->orderBy('day')->get(),
            'appointments' => Appointment::query()
                ->whereBetween('created_at', [$from, $to])
                ->select(DB::raw('DATE(created_at) as day'), DB::raw('COUNT(*) as value'))
                ->groupBy('day')->orderBy('day')->get(),
            default => collect(),
        };

        return $this->success([
            'metric' => $metric,
            'series' => $rows->map(fn ($r) => ['day' => $r->day, 'value' => (int) $r->value])->all(),
        ]);
    }
}
