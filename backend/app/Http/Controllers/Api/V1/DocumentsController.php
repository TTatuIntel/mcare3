<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Resources\MedicalDocumentResource;
use App\Models\MedicalDocument;
use App\Support\ApiResponse;
use App\Support\MedicalDocumentFiles;
use Illuminate\Http\Request;

class DocumentsController extends Controller
{
    use ApiResponse;

    public function store(Request $request)
    {
        $data = MedicalDocumentFiles::validateMeta($request, requireFile: true);
        $stored = MedicalDocumentFiles::storeUploadedFile($request, $request->user()->id);

        $doc = $request->user()->medicalDocuments()->create([
            'title' => $data['title'],
            'category' => $data['category'],
            'file_type' => $data['file_type'],
            'storage_path' => $stored['path'],
            'size_bytes' => $stored['size'],
            'description' => $data['description'] ?? null,
            'shared_with_doctor_id' => $data['shared_with_doctor_id'] ?? null,
            'uploaded_by' => $request->user()->fullName(),
            'uploaded_at' => now(),
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
        MedicalDocumentFiles::deleteStoredFile($document->storage_path);
        $document->delete();

        return $this->success(null, 'Document deleted.');
    }

    public function stream(Request $request, MedicalDocument $document)
    {
        abort_unless($document->user_id === $request->user()->id, 403);
        if ($error = MedicalDocumentFiles::streamError($document)) {
            return $error;
        }

        return MedicalDocumentFiles::stream($document);
    }

    public function downloadUrl(Request $request, MedicalDocument $document)
    {
        abort_unless($document->user_id === $request->user()->id, 403);
        if (! $document->storage_path) {
            return $this->error('No file attached.', 404);
        }

        return $this->success([
            'url' => url('/api/v1/patient/documents/'.$document->id.'/stream'),
        ]);
    }
}
