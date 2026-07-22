<?php

namespace App\Http\Controllers\Api\V1\Admin;

use App\Http\Controllers\Controller;
use App\Models\AuditEntry;
use App\Support\ApiResponse;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\StreamedResponse;

class AuditController extends Controller
{
    use ApiResponse;

    public function index(Request $request)
    {
        $query = AuditEntry::query()->orderByDesc('happened_at');

        if ($category = $request->query('category')) {
            $query->where('category', $category);
        }
        if ($action = $request->query('action')) {
            $query->where('action', 'like', '%'.$action.'%');
        }
        if ($from = $request->query('from')) {
            $query->where('happened_at', '>=', $from);
        }
        if ($to = $request->query('to')) {
            $query->where('happened_at', '<=', $to);
        }
        if ($actor = $request->query('actor')) {
            $query->where('actor_label', 'like', '%'.$actor.'%');
        }

        $page = max(1, (int) $request->query('page', 1));
        $perPage = min(200, max(20, (int) $request->query('per_page', 50)));

        $total = $query->count();
        $items = $query->forPage($page, $perPage)->get()
            ->map(fn (AuditEntry $e) => $e->toApiArray());

        return $this->success([
            'audit' => $items,
            'meta' => ['page' => $page, 'per_page' => $perPage, 'total' => $total],
        ]);
    }

    public function export(Request $request): StreamedResponse
    {
        $query = AuditEntry::query()->orderBy('happened_at');
        if ($from = $request->query('from')) {
            $query->where('happened_at', '>=', $from);
        }
        if ($to = $request->query('to')) {
            $query->where('happened_at', '<=', $to);
        }

        $filename = 'audit-'.now()->format('Ymd-His').'.csv';

        return response()->streamDownload(function () use ($query) {
            $out = fopen('php://output', 'w');
            fputcsv($out, ['id', 'happened_at', 'actor', 'action', 'target', 'category']);
            $query->chunk(500, function ($chunk) use ($out) {
                foreach ($chunk as $e) {
                    fputcsv($out, [
                        $e->id,
                        $e->happened_at?->toIso8601String(),
                        $e->actor_label,
                        $e->action,
                        $e->target,
                        $e->category,
                    ]);
                }
            });
            fclose($out);
        }, $filename, ['Content-Type' => 'text/csv']);
    }
}
