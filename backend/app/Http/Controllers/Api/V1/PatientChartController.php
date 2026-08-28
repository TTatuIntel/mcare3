<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\ClinicalReport;
use App\Models\User;
use App\Services\AuditService;
use App\Services\PatientChartService;
use App\Support\ApiResponse;
use App\Support\SosRoles;
use Carbon\Carbon;
use Illuminate\Http\Request;

/**
 * The clinical chart behind "Open the patient chart".
 *
 * Same payload for a doctor and for a coordinator, because the question they
 * are answering — what is going on with this patient, right now and over the
 * last however-many days — is the same question. Access differs, and only
 * access: a doctor is held to their own caseload, a coordinator is not.
 *
 * Reading a patient's chart is a disclosure, so every read is audited.
 */
class PatientChartController extends Controller
{
    use ApiResponse;

    /** Longest window the chart will assemble in one read. */
    private const MAX_DAYS = 366;

    public function __construct(
        private readonly PatientChartService $charts,
        private readonly AuditService $audit,
    ) {}

    public function show(Request $request, User $patient)
    {
        $actor = $request->user();
        $this->authorizePatient($actor, $patient);

        [$from, $to] = $this->window($request);

        $chart = $this->charts->build($patient, $from, $to);

        $this->audit->record(
            $actor,
            'patient.chart_viewed',
            $patient->fullName(),
            'security',
            [
                'patient_user_id' => $patient->id,
                'target_user_id' => $patient->id,
                'from' => $from->toIso8601String(),
                'to' => $to->toIso8601String(),
            ],
        );

        return $this->success($chart);
    }

    /**
     * A note written from the chart, against the period the author was
     * looking at. Stored as a clinical report so it is the same object the
     * report builder already draws its notes section from — a note worth
     * writing during an emergency is exactly the note a report should carry.
     */
    public function storeNote(Request $request, User $patient)
    {
        $actor = $request->user();
        $this->authorizePatient($actor, $patient);

        $data = $request->validate([
            'title' => 'required|string|max:200',
            'body' => 'required|string|max:5000',
            'publish' => 'nullable|boolean',
        ]);

        $publish = (bool) ($data['publish'] ?? false);

        $note = ClinicalReport::create([
            'patient_user_id' => $patient->id,
            'author_user_id' => $actor->id,
            'title' => $data['title'],
            'body' => $data['body'],
            'published' => $publish,
            'published_at' => $publish ? now() : null,
        ]);

        $this->audit->record(
            $actor,
            $publish ? 'patient.note_published' : 'patient.note_drafted',
            $patient->fullName().' — '.$note->title,
            'activity',
            ['patient_user_id' => $patient->id, 'report_id' => $note->id],
        );

        return $this->success(
            ['note' => $note->toApiArray() + ['author_name' => $actor->fullName()]],
            $publish ? 'Note saved and shared.' : 'Note saved to the chart.',
            201,
        );
    }

    private function authorizePatient(User $actor, User $patient): void
    {
        abort_unless($patient->role === 'patient', 404, 'Not a patient account.');

        if (SosRoles::isCoordinator($actor)) {
            return;
        }

        abort_unless($actor->role === 'doctor', 403, 'Not a clinician.');
        DoctorAccess::assertCaseload($actor, $patient->id);
    }

    /**
     * The period the chart covers. Defaults to 30 days because that is the
     * span the vitals summaries elsewhere already reason about; anything the
     * caller asks for is clamped rather than refused, so a filter can never
     * leave the responder staring at an error instead of a chart.
     *
     * @return array{0: Carbon, 1: Carbon}
     */
    private function window(Request $request): array
    {
        $data = $request->validate([
            'from' => 'nullable|date',
            'to' => 'nullable|date',
            'days' => 'nullable|integer|min:1|max:'.self::MAX_DAYS,
        ]);

        $to = isset($data['to']) ? Carbon::parse($data['to'])->endOfDay() : Carbon::now();

        if (isset($data['from'])) {
            $from = Carbon::parse($data['from'])->startOfDay();
        } else {
            $from = (clone $to)->subDays((int) ($data['days'] ?? 30));
        }

        if ($from->greaterThan($to)) {
            [$from, $to] = [$to, $from];
        }
        if ($from->diffInDays($to) > self::MAX_DAYS) {
            $from = (clone $to)->subDays(self::MAX_DAYS);
        }

        return [$from, $to];
    }
}
