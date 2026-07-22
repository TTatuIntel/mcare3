<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\AppNotification;
use App\Models\ClinicalReport;
use App\Support\ApiResponse;
use Illuminate\Http\Request;

class DoctorReportsController extends Controller
{
    use ApiResponse;

    public function index(Request $request)
    {
        return $this->success([
            'reports' => ClinicalReport::where('author_user_id', $request->user()->id)
                ->orderByDesc('created_at')
                ->limit(200)
                ->get()
                ->map->toApiArray()
                ->all(),
        ]);
    }

    public function store(Request $request)
    {
        $data = $request->validate([
            'patient_user_id' => 'required|integer|exists:users,id',
            'title' => 'required|string|max:200',
            'body' => 'required|string',
            'publish' => 'nullable|boolean',
        ]);

        DoctorAccess::assertCaseload($request->user(), (int) $data['patient_user_id']);

        $publish = (bool) ($data['publish'] ?? false);
        $report = ClinicalReport::create([
            'patient_user_id' => $data['patient_user_id'],
            'author_user_id' => $request->user()->id,
            'title' => $data['title'],
            'body' => $data['body'],
            'published' => $publish,
            'published_at' => $publish ? now() : null,
        ]);

        if ($publish) {
            $this->notifyPatient($report);
        }
        DoctorAccess::audit(
            $request->user(),
            $publish ? 'Published clinical report' : 'Drafted clinical report',
            "Patient #{$report->patient_user_id} — {$report->title}"
        );

        return $this->success(['report' => $report->toApiArray()], 'Report saved.', 201);
    }

    public function update(Request $request, ClinicalReport $report)
    {
        $this->authorizeAuthor($request, $report);
        $data = $request->validate([
            'title' => 'nullable|string|max:200',
            'body' => 'nullable|string',
        ]);
        $report->update(array_filter($data, fn ($v) => $v !== null));
        return $this->success(['report' => $report->fresh()->toApiArray()], 'Report updated.');
    }

    public function publish(Request $request, ClinicalReport $report)
    {
        $this->authorizeAuthor($request, $report);
        if (! $report->published) {
            $report->update(['published' => true, 'published_at' => now()]);
            $this->notifyPatient($report->fresh());
            DoctorAccess::audit(
                $request->user(),
                'Published clinical report',
                "Patient #{$report->patient_user_id} — {$report->title}"
            );
        }
        return $this->success(['report' => $report->fresh()->toApiArray()], 'Report published.');
    }

    public function destroy(Request $request, ClinicalReport $report)
    {
        $this->authorizeAuthor($request, $report);
        abort_if($report->published, 409, 'Published reports cannot be deleted.');
        $report->delete();
        return $this->success(null, 'Draft deleted.');
    }

    private function authorizeAuthor(Request $request, ClinicalReport $report): void
    {
        abort_unless(
            $report->author_user_id === $request->user()->id,
            403,
            'You can only modify your own reports.'
        );
    }

    private function notifyPatient(ClinicalReport $report): void
    {
        AppNotification::create([
            'user_id' => $report->patient_user_id,
            'kind' => 'report',
            'title' => 'New clinical report',
            'body' => $report->title,
            'action_route' => '/patient/documents',
            'action_arguments' => ['report_id' => (string) $report->id],
            'read' => false,
        ]);
    }
}
