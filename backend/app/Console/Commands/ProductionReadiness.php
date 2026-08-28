<?php

namespace App\Console\Commands;

use App\Support\ProductionReadiness as ReadinessAudit;
use Illuminate\Console\Command;

class ProductionReadiness extends Command
{
    protected $signature = 'mcare:readiness {--json : Emit machine-readable JSON} {--strict : Fail unless every gate passes}';

    protected $description = 'Audit secret-free production configuration and runtime readiness';

    public function handle(): int
    {
        $checks = ReadinessAudit::audit();
        $summary = [
            'pass' => collect($checks)->where('status', 'pass')->count(),
            'warn' => collect($checks)->where('status', 'warn')->count(),
            'fail' => collect($checks)->where('status', 'fail')->count(),
        ];

        if ($this->option('json')) {
            $this->line((string) json_encode([
                'ready' => $summary['fail'] === 0 && (! $this->option('strict') || $summary['warn'] === 0),
                'summary' => $summary,
                'checks' => $checks,
            ], JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES));
        } else {
            $this->table(['Gate', 'Status', 'Detail'], array_map(
                fn (array $check) => [$check['gate'], strtoupper($check['status']), $check['detail']],
                $checks,
            ));
            $this->newLine();
            $this->line("PASS {$summary['pass']} | WARN {$summary['warn']} | FAIL {$summary['fail']}");
        }

        if (! $this->option('strict')) {
            return self::SUCCESS;
        }

        return $summary['fail'] === 0 && $summary['warn'] === 0
            ? self::SUCCESS
            : self::FAILURE;
    }
}
