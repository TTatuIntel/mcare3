<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Resources\MedicalDocumentResource;
use App\Models\MedicalDocument;
use App\Support\ApiResponse;
use App\Support\DocumentRemoval;
use App\Support\MedicalDocumentFiles;
use Illuminate\Http\Request;

class DocumentsController extends Controller
{
    use ApiResponse;

    /**
     * The patient's own documents, newest first.
     *
     * Everything in the patient app was reachable only through
     * `GET /patient/session`, which returns twenty-one collections at once. A
     * doctor filing a lab result therefore could not be picked up without
     * refetching the whole record — and the notification that announces it
     * routes straight to the documents screen. This is the list that screen
     * needs, and nothing more.
     */
    public function index(Request $request)
    {
        $documents = $request->user()->medicalDocuments()
            ->orderByDesc('uploaded_at')
            ->get();

        return $this->success([
            'documents' => MedicalDocumentResource::collection($documents),
        ]);
    }

    public function store(Request $request)
    {
        $data = MedicalDocumentFiles::validateMeta($request, requireFile: true);
        $stored = MedicalDocumentFiles::storeUploadedFile($request, $request->user()->id);

        $doc = $request->user()->medicalDocuments()->create([
            'title' => $data['title'],
            'category' => $data['category'],
            'file_type' => $data['file_type'],
            // The real type and the name the file arrived under, so opening it
            // again months later hands the browser or the share sheet what was
            // actually stored rather than a guess made from `file_type`.
            'mime_type' => $stored['mime'],
            'original_filename' => $stored['original_name'],
            'storage_path' => $stored['path'],
            'size_bytes' => $stored['size'],
            'description' => $data['description'] ?? null,
            'shared_with_doctor_id' => $data['shared_with_doctor_id'] ?? null,
            'uploaded_by' => $request->user()->fullName(),
            'uploaded_at' => now(),
            // Their own file. The one case that stays deletable.
            'source' => MedicalDocument::SOURCE_PATIENT,
        ]);

        return $this->success(['document' => new MedicalDocumentResource($doc)], 'Document uploaded.', 201);
    }

    public function update(Request $request, MedicalDocument $document)
    {
        abort_unless($document->user_id === $request->user()->id, 403);
        $data = MedicalDocumentFiles::validateUpdate($request);
        MedicalDocumentFiles::applyUpdate($document, $data, $request, $request->user()->id);

        return $this->success(['document' => new MedicalDocumentResource($document->fresh())], 'Document updated.');
    }

    public function destroy(Request $request, MedicalDocument $document)
    {
        abort_unless($document->user_id === $request->user()->id, 403);

        // Own file: theirs to remove. Anything a clinician filed, and above all
        // an issued report, is the record of something that happened and stays.
        if (! $document->isDeletableBy($request->user())) {
            return $this->error($document->deleteRefusalReason(), 403, [
                // A refusal that names the way forward. A patient looking at a
                // document filed against them in error needs a route, not a no.
                'can_request_removal' => $document->canRequestRemoval(),
                'removal_requested' => $document->removalPending(),
            ]);
        }

        MedicalDocumentFiles::deleteStoredFile($document->storage_path);
        $document->delete();

        return $this->success(null, 'Document deleted.');
    }

    /**
     * Ask the care team to take a document out of the record.
     *
     * The patient cannot delete a clinician-filed document themselves and
     * should not be able to — but a result filed against the wrong person, or a
     * letter naming someone else, is theirs to get removed. This is the request
     * that makes staff deletion possible at all; without a standing one, every
     * staff-side delete path refuses.
     */
    public function requestRemoval(Request $request, MedicalDocument $document)
    {
        abort_unless($document->user_id === $request->user()->id, 403);

        $data = $request->validate([
            'reason' => 'required|string|min:4|max:280',
        ]);

        if ($document->isDeletableBy($request->user())) {
            return $this->error(
                'This is your own upload — you can delete it yourself.',
                422,
            );
        }
        if ($document->source === MedicalDocument::SOURCE_REPORT) {
            return $this->error($document->deleteRefusalReason(), 422);
        }
        if ($document->removalPending()) {
            return $this->error(
                'You have already asked for this document to be removed. '
                .'Your care team has been told.',
                422,
            );
        }

        DocumentRemoval::request($document, trim($data['reason']));

        return $this->success(
            ['document' => new MedicalDocumentResource($document->fresh())],
            'Your care team has been asked to remove this document.',
        );
    }

    /** Withdraw a removal request before staff have answered it. */
    public function cancelRemoval(Request $request, MedicalDocument $document)
    {
        abort_unless($document->user_id === $request->user()->id, 403);

        if (! $document->removalPending()) {
            return $this->error('There is no removal request to cancel.', 422);
        }

        DocumentRemoval::withdraw($document);

        return $this->success(
            ['document' => new MedicalDocumentResource($document->fresh())],
            'Removal request withdrawn.',
        );
    }

    /**
     * The file itself.
     *
     * `?download=1` asks for it as an attachment. Without that distinction
     * Download and View were the same request with the same `inline`
     * disposition, so "Download" opened a tab and the patient — standing at a
     * hospital reception being asked for their discharge summary — never got a
     * file onto their device at all.
     */
    public function stream(Request $request, MedicalDocument $document)
    {
        abort_unless($document->user_id === $request->user()->id, 403);
        if ($error = MedicalDocumentFiles::streamError($document)) {
            return $error;
        }

        return MedicalDocumentFiles::stream($document, $request->boolean('download'));
    }

    public function downloadUrl(Request $request, MedicalDocument $document)
    {
        abort_unless($document->user_id === $request->user()->id, 403);
        if (! $document->storage_path) {
            return $this->error('No file attached.', 404);
        }

        return $this->success([
            'url' => url('/api/v1/patient/documents/'.$document->id.'/stream'),
            'download_name' => $document->downloadName(),
            'mime_type' => MedicalDocumentFiles::mimeFor($document),
        ]);
    }
}
