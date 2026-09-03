<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\AuditEntry;
use App\Models\CareAssignment;
use App\Models\CareProvider;
use App\Models\PatientReportRequest;
use App\Models\User;
use App\Services\AuditService;
use App\Services\PatientReportService;
use App\Services\UserDossierService;
use App\Support\ApiResponse;
use App\Support\PatientReportSections;
use Illuminate\Http\Request;

/**
 * The patient's own clinical record, in the same shape staff read.
 *
 * Admins and doctors have had a complete dossier of a patient for a while —
 * health profile, vitals, medications, care team, appointments, documents,
 * alerts, account and sign-in history — while the person the record describes
 * could only see fragments of it spread across four screens. This serves the
 * identical payload to its subject, so the patient reads exactly what their
 * clinic reads about them rather than a summary somebody decided was enough.
 *
 * Two things differ from the staff route, both deliberate:
 *  - unpublished clinical notes are withheld (a working note is not a record
 *    until its author says it is), which the dossier service handles via its
 *    self-view flag;
 *  - the read is audited against the patient themselves, so "who opened this
 *    record" stays answerable and self-access is distinguishable from staff
 *    access in the trail.
 */
class PatientRecordController extends Controller
{
    use ApiResponse;

    /** Open patient-raised report requests allowed at once. */
    private const OPEN_REQUEST_LIMIT = 1;

    public function __construct(
        private readonly UserDossierService $dossiers,
        private readonly PatientReportService $reports,
        private readonly AuditService $audit,
    ) {}

    public function show(Request $request)
    {
        $user = $request->user();

        $dossier = $this->dossiers->build($user, selfView: true);

        // What the "request a full report" panel needs to render honestly:
        // who would sign it, and whether one is already in flight.
        $dossier['report_access'] = $this->reportAccess($user);

        $this->recordSelfView($user);

        return $this->success($dossier);
    }

    /**
     * The patient asking for a complete report of their own record.
     *
     * It takes the same route as one an admin raises — a care-team doctor
     * signs, an admin issues — because a report leaving the platform should
     * be read by a clinician first regardless of who asked for it. The reason
     * the patient gives becomes the request's stated purpose, so the doctor
     * signing it knows what it is for.
     */
    public function requestReport(Request $request)
    {
        $user = $request->user();

        $data = $request->validate([
            'reason' => 'required|string|min:10|max:280',
            'recipient' => 'nullable|string|max:160',
        ]);

        $doctor = $this->preferredSigner($user);
        if (! $doctor) {
            return $this->error(
                'You do not have a doctor assigned yet, and a report has to be '
                .'signed by one before it can be issued. Request a provider '
                .'from your care team first.',
                422,
            );
        }

        if ($this->openRequestCount($user) >= self::OPEN_REQUEST_LIMIT) {
            return $this->error(
                'You already have a report request in progress. You will be '
                .'notified when it is ready — there is no need to ask again.',
                422,
            );
        }

        $reportRequest = $this->reports->create(
            $user,
            $user,
            PatientReportSections::keys(),
            'Full health record — '.$user->fullName(),
            trim($data['reason']),
            $data['recipient'] ?? null,
            $doctor,
        );

        return $this->success(
            [
                'report_request' => $reportRequest->toPatientApiArray(),
                'report_access' => $this->reportAccess($user),
            ],
            'Sent to Dr. '.$doctor->fullName().' to review and sign.',
            201,
        );
    }

    /**
     * Log that the patient opened their own record — at most once an hour.
     *
     * The page refreshes itself on every realtime event touching vitals,
     * medications, documents or care, so auditing each fetch would write
     * dozens of rows for one sitting and bury the staff accesses that are the
     * reason this trail exists. One row per session-ish window answers the
     * only question worth asking of it: was this record read by its subject,
     * and when.
     */
    private function recordSelfView(User $user): void
    {
        $seenRecently = AuditEntry::where('actor_user_id', $user->id)
            ->where('action', 'patient.record_self_viewed')
            ->where('happened_at', '>=', now()->subHour())
            ->exists();

        if ($seenRecently) {
            return;
        }

        $this->audit->record(
            $user,
            'patient.record_self_viewed',
            $user->fullName(),
            'security',
            [
                'patient_user_id' => $user->id,
                'target_user_id' => $user->id,
            ],
        );
    }

    /**
     * Whether this patient can raise a report right now, and why not if they
     * cannot. Computed server-side so the button and the endpoint can never
     * disagree about what is allowed.
     *
     * @return array<string, mixed>
     */
    private function reportAccess(User $user): array
    {
        $doctor = $this->preferredSigner($user);
        $open = $this->openRequestCount($user);

        return [
            'can_request' => $doctor !== null && $open < self::OPEN_REQUEST_LIMIT,
            'signer_name' => $doctor?->fullName(),
            'has_care_team' => $doctor !== null,
            'open_requests' => $open,
            'sections' => array_map(fn (string $key) => [
                'key' => $key,
                'label' => PatientReportSections::label($key),
                'description' => PatientReportSections::CATALOG[$key]['description'] ?? '',
            ], PatientReportSections::keys()),
        ];
    }

    /**
     * Requests this patient raised that have not finished yet.
     *
     * Only their own: a report an admin is preparing about them is not
     * something the patient asked for, and should not block them asking.
     */
    private function openRequestCount(User $user): int
    {
        return PatientReportRequest::where('patient_user_id', $user->id)
            ->where('requested_by_user_id', $user->id)
            ->whereNull('issued_at')
            ->whereNotIn('status', [
                PatientReportRequest::STATUS_DECLINED,
                PatientReportRequest::STATUS_EXPIRED,
                PatientReportRequest::STATUS_REVOKED,
                PatientReportRequest::STATUS_ISSUED,
            ])
            ->count();
    }

    /**
     * The doctor who would sign: the patient's primary if they have one, the
     * most recently assigned otherwise. Healthworkers and ended assignments
     * can sign nothing, so they are never considered.
     */
    private function preferredSigner(User $user): ?User
    {
        $assignments = CareAssignment::where('patient_user_id', $user->id)
            ->whereNull('ended_at')
            ->orderByRaw("CASE WHEN LOWER(role) = 'primary' THEN 0 ELSE 1 END")
            ->orderByDesc('assigned_at')
            ->get();

        foreach ($assignments as $assignment) {
            $providerUserId = CareProvider::find($assignment->provider_id)?->user_id;
            if (! $providerUserId) {
                continue;
            }
            $doctor = User::find($providerUserId);
            if ($doctor && $doctor->role === 'doctor') {
                return $doctor;
            }
        }

        return null;
    }
}
