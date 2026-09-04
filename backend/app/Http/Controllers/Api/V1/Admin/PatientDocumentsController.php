<?php

namespace App\Http\Controllers\Api\V1\Admin;

use App\Http\Controllers\Concerns\ManagesPatientDocuments;
use App\Http\Controllers\Controller;
use App\Models\MedicalDocument;
use App\Models\User;
use App\Services\AuditService;
use App\Support\ApiResponse;
use Illuminate\Http\Request;

/**
 * Lets admin / mCare assistant staff file documents into a patient's record.
 *
 * Doctors could already do this and admins could not, which left the paperwork
 * that is not a doctor's to send — an insurance letter, a scanned consent, a
 * corrected lab result received by the office — with no route into the record
 * at all. Staff were reduced to emailing it, which puts clinical documents
 * outside the audited store entirely.
 *
 * Nothing in a patient's record disappears on staff say-so: a wrong document is
 * superseded by a corrected upload and a report that should not have gone out is
 * revoked — both leave a trace, which deletion does not. The one exception is
 * honouring a removal, and it is not staff-initiated: it requires a standing
 * request from the patient, which is the only authority that can take a document
 * out of their own record.
 *
 * The rules themselves live in {@see ManagesPatientDocuments}, shared with the
 * doctor routes. This class supplies only what is genuinely different about
 * admin staff: they are not on a caseload — which is the whole reason these
 * routes exist — so access is gated by the route's permission middleware, and
 * the patient is shown a label that says so.
 */
class PatientDocumentsController extends Controller
{
    use ApiResponse;
    use ManagesPatientDocuments;

    public function __construct(protected readonly AuditService $audit) {}

    /**
     * Admin staff are not on a caseload; the route's permission middleware is
     * the gate, and re-checking here would refuse every legitimate caller.
     */
    protected function assertPatientDocumentAccess(Request $request, User $patient): void
    {
        // Intentionally empty — see the class docblock.
    }

    /**
     * Patients read this string in their documents list, so it says the role
     * rather than a bare name — "who sent me this?" is the first question.
     */
    protected function documentActorLabel(Request $request): string
    {
        $user = $request->user();
        $role = $user->role === 'mcare_assistant' ? 'mCare team' : 'mCare admin';

        return $role.' · '.$user->fullName();
    }

    protected function documentStreamUrl(User $patient, MedicalDocument $document): string
    {
        return url('/api/v1/admin/patients/'.$patient->id.'/documents/'.$document->id.'/stream');
    }

    protected function recordDocumentAudit(
        Request $request,
        User $patient,
        MedicalDocument $document,
        string $action,
    ): void {
        $this->audit->record(
            $request->user(),
            'patient.document_'.$action,
            $document->title.' for '.$patient->fullName(),
            'activity',
            [
                'patient_user_id' => $patient->id,
                'target_user_id' => $patient->id,
                'document_id' => $document->id,
                'category' => $document->category,
            ],
        );
    }
}
