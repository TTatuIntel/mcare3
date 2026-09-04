<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\AppNotification;
use App\Models\DocumentRequest;
use App\Models\MedicalDocument;
use App\Models\RequestActivityEvent;
use App\Support\ApiResponse;
use App\Support\DocumentDelivery;
use App\Support\MedicalDocumentFiles;
use Illuminate\Http\Request;

/**
 * The care team answering a patient's request for a document.
 *
 * Shares its shape with {@see DoctorVitalReportRequestsController} on purpose:
 * the same shared-queue-with-single-owner rule, the same claim before you can
 * finish, the same trail the patient can read. A clinician who has learned one
 * of these queues has learned both.
 *
 * Declining is a first-class outcome here in a way it is not for a vital
 * report. Some documents genuinely cannot be produced — a letter the practice
 * has no basis to write, a record held by another provider — and a patient
 * left watching "pending" forever is worse served than one told no and why.
 */
class DoctorDocumentRequestsController extends Controller
{
    use ApiResponse;

    public function index(Request $request)
    {
        $patientIds = DoctorAccess::caseloadPatientIds($request->user());

        $requests = DocumentRequest::with(['events', 'patient', 'targetDoctor'])
            ->whereIn('user_id', $patientIds)
            ->orderByRaw("CASE WHEN status IN ('pending','in_progress') THEN 0 ELSE 1 END")
            ->orderByDesc('created_at')
            ->get();

        return $this->success([
            'requests' => $requests
                ->map(fn (DocumentRequest $r) => $r->toStaffArray($request->user()))
                ->all(),
        ]);
    }

    public function claim(Request $request, DocumentRequest $documentRequest)
    {
        DoctorAccess::assertCaseload($request->user(), $documentRequest->user_id);

        if (! $documentRequest->isOpen()) {
            return $this->error('This request has already been closed.', 422, [
                'request' => $documentRequest->load('events')->toStaffArray($request->user()),
            ]);
        }

        $label = 'Dr. '.$request->user()->fullName();

        if (! $documentRequest->claimFor($request->user(), $label)) {
            $holder = $documentRequest->fresh();

            return $this->error(
                ($holder->claimed_by_name ?? 'Another clinician').' is already working on this request.',
                409,
                ['request' => $holder->load('events')->toStaffArray($request->user())],
            );
        }

        DoctorAccess::audit(
            $request->user(),
            'Claimed document request',
            "Request #{$documentRequest->id}",
        );

        $this->tellPatient(
            $documentRequest,
            'Your document request was picked up',
            $label.' is preparing "'.$documentRequest->title.'".',
        );

        return $this->success(
            ['request' => $documentRequest->fresh()->load('events')->toStaffArray($request->user())],
            'You are now working on this request.',
        );
    }

    public function release(Request $request, DocumentRequest $documentRequest)
    {
        DoctorAccess::assertCaseload($request->user(), $documentRequest->user_id);

        if (! $documentRequest->isClaimedBy($request->user())) {
            return $this->error('You are not the one working on this request.', 403);
        }

        $data = $request->validate(['note' => 'nullable|string|max:280']);

        $documentRequest->release(
            $request->user(),
            'Dr. '.$request->user()->fullName(),
            $data['note'] ?? null,
        );

        DoctorAccess::audit(
            $request->user(),
            'Released document request',
            "Request #{$documentRequest->id}",
        );

        return $this->success(
            ['request' => $documentRequest->fresh()->load('events')->toStaffArray($request->user())],
            'Request returned to the care team queue.',
        );
    }

    /**
     * Answer it with the file, in one step.
     *
     * Uploading the document and closing the request are the same act, so they
     * are one call. Splitting them left a filed document with a request still
     * showing "pending" beside it whenever the second call was lost, which is
     * precisely the state the patient reads as "nobody has done anything".
     */
    public function fulfill(Request $request, DocumentRequest $documentRequest)
    {
        DoctorAccess::assertCaseload($request->user(), $documentRequest->user_id);

        if (! $documentRequest->isOpen()) {
            return $this->error('This request has already been closed.', 422, [
                'request' => $documentRequest->load('events')->toStaffArray($request->user()),
            ]);
        }

        if ($documentRequest->isClaimed() && ! $documentRequest->isClaimedBy($request->user())) {
            return $this->error(
                $documentRequest->claimed_by_name.' is working on this request. '
                .'Ask them to hand it back before completing it.',
                409,
                ['request' => $documentRequest->load('events')->toStaffArray($request->user())],
            );
        }

        $data = MedicalDocumentFiles::validateMeta($request, requireFile: true);
        $note = $request->validate(['note' => 'nullable|string|max:1000'])['note'] ?? null;

        $label = 'Dr. '.$request->user()->fullName();

        if (! $documentRequest->isClaimed()
            && ! $documentRequest->claimFor($request->user(), $label)) {
            $holder = $documentRequest->fresh();

            return $this->error(
                ($holder->claimed_by_name ?? 'Another clinician').' just took this request on.',
                409,
                ['request' => $holder->load('events')->toStaffArray($request->user())],
            );
        }

        $stored = MedicalDocumentFiles::storeUploadedFile($request, $documentRequest->user_id);

        $document = MedicalDocument::create([
            'user_id' => $documentRequest->user_id,
            'title' => $data['title'],
            'category' => $data['category'],
            'file_type' => $data['file_type'],
            'storage_path' => $stored['path'],
            'size_bytes' => $stored['size'],
            'description' => $data['description'] ?? 'Provided in answer to your request "'
                .$documentRequest->title.'".',
            'uploaded_by' => $label,
            'uploaded_at' => now(),
            // Filed by a clinician, so it is part of the clinical record from
            // this moment and follows the same removal rules as any other.
            'source' => MedicalDocument::SOURCE_CLINICIAN,
        ]);

        $documentRequest->update([
            'status' => DocumentRequest::FULFILLED,
            'resolved_at' => now(),
            'resolved_by_name' => $label,
            'resolution_note' => $note,
            'document_id' => $document->id,
        ]);

        RequestActivityEvent::record(
            $documentRequest,
            RequestActivityEvent::RESOLVED,
            $label,
            $request->user()->id,
            $note,
        );

        DoctorAccess::audit(
            $request->user(),
            'Fulfilled document request',
            $document->title.' for request #'.$documentRequest->id,
        );

        DocumentDelivery::notifyOwner($document, $label);

        return $this->success([
            'request' => $documentRequest->fresh()->load('events')->toStaffArray($request->user()),
            'document' => $document->toApiArray(),
        ], 'Document filed and request closed.', 201);
    }

    /**
     * Say no, with a reason.
     *
     * The reason is required and the patient reads it verbatim. A decline with
     * no explanation is indistinguishable from being ignored, and the patient
     * cannot tell whether to ask again, ask elsewhere, or stop asking.
     */
    public function decline(Request $request, DocumentRequest $documentRequest)
    {
        DoctorAccess::assertCaseload($request->user(), $documentRequest->user_id);

        if (! $documentRequest->isOpen()) {
            return $this->error('This request has already been closed.', 422, [
                'request' => $documentRequest->load('events')->toStaffArray($request->user()),
            ]);
        }

        if ($documentRequest->isClaimed() && ! $documentRequest->isClaimedBy($request->user())) {
            return $this->error(
                $documentRequest->claimed_by_name.' is working on this request.',
                409,
                ['request' => $documentRequest->load('events')->toStaffArray($request->user())],
            );
        }

        $data = $request->validate([
            'reason' => 'required|string|min:4|max:280',
        ]);

        $label = 'Dr. '.$request->user()->fullName();

        $documentRequest->update([
            'status' => DocumentRequest::DECLINED,
            'resolved_at' => now(),
            'resolved_by_name' => $label,
            'decline_reason' => trim($data['reason']),
            'claimed_by' => null,
            'claimed_by_name' => null,
            'claimed_at' => null,
        ]);

        RequestActivityEvent::record(
            $documentRequest,
            RequestActivityEvent::DECLINED,
            $label,
            $request->user()->id,
            trim($data['reason']),
        );

        DoctorAccess::audit(
            $request->user(),
            'Declined document request',
            "Request #{$documentRequest->id}",
        );

        $this->tellPatient(
            $documentRequest,
            'Your document request was answered',
            $label.' could not provide "'.$documentRequest->title.'": '.trim($data['reason']),
        );

        return $this->success(
            ['request' => $documentRequest->fresh()->load('events')->toStaffArray($request->user())],
            'Request declined and the patient told why.',
        );
    }

    private function tellPatient(DocumentRequest $req, string $title, string $body): void
    {
        try {
            AppNotification::create([
                'user_id' => $req->user_id,
                'kind' => 'document',
                'title' => $title,
                'body' => $body,
                'action_route' => '/patient/documents',
                'read' => false,
            ]);
        } catch (\Throwable $e) {
            report($e);
        }
    }
}
