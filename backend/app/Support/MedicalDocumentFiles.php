<?php

namespace App\Support;

use App\Models\MedicalDocument;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use Symfony\Component\HttpFoundation\StreamedResponse;

class MedicalDocumentFiles
{
    public const ALLOWED_MIMES = 'pdf,jpg,jpeg,png,doc,docx';

    public static function validateMeta(Request $request, bool $requireFile = false): array
    {
        return $request->validate([
            'title' => 'required|string|max:200',
            'category' => 'required|string|in:labResult,prescription,imaging,discharge,consultationNote,other',
            'file_type' => 'required|string|in:pdf,image,doc,other',
            'description' => 'nullable|string',
            'shared_with_doctor_id' => 'nullable|exists:users,id',
            'file' => ($requireFile ? 'required' : 'nullable').'|file|max:10240|mimes:'.self::ALLOWED_MIMES,
        ]);
    }

    public static function validateUpdate(Request $request): array
    {
        return $request->validate([
            'title' => 'sometimes|string|max:200',
            'category' => 'sometimes|string|in:labResult,prescription,imaging,discharge,consultationNote,other',
            'file_type' => 'sometimes|string|in:pdf,image,doc,other',
            'description' => 'nullable|string',
            'file' => 'nullable|file|max:10240|mimes:'.self::ALLOWED_MIMES,
        ]);
    }

    public static function storeUploadedFile(Request $request, int $ownerUserId): array
    {
        $f = $request->file('file');
        $path = $f->store('documents/'.$ownerUserId, self::privateDiskName());

        return ['path' => $path, 'size' => $f->getSize()];
    }

    public static function deleteStoredFile(?string $path): void
    {
        if ($path) {
            Storage::disk(self::privateDiskName())->delete($path);
            // Compatibility cleanup for files created before private storage.
            if (self::privateDiskName() !== 'public') {
                Storage::disk('public')->delete($path);
            }
        }
    }

    public static function streamError(MedicalDocument $document): ?JsonResponse
    {
        if (! $document->storage_path) {
            return response()->json([
                'success' => false,
                'data' => null,
                'message' => 'No file attached to this document.',
            ], 404);
        }

        if (! self::exists($document->storage_path)) {
            return response()->json([
                'success' => false,
                'data' => null,
                'message' => 'Document file not found on server.',
            ], 404);
        }

        return null;
    }

    public static function stream(MedicalDocument $document): StreamedResponse
    {
        $disk = Storage::disk(self::diskContaining($document->storage_path));

        $mime = $disk->mimeType($document->storage_path) ?: 'application/octet-stream';
        $filename = basename($document->storage_path);

        return response()->stream(function () use ($disk, $document) {
            $stream = $disk->readStream($document->storage_path);
            if ($stream !== false) {
                fpassthru($stream);
                fclose($stream);
            }
        }, 200, [
            'Content-Type' => $mime,
            'Content-Disposition' => 'inline; filename="'.$filename.'"',
            'Cache-Control' => 'private, max-age=3600',
        ]);
    }

    public static function applyUpdate(MedicalDocument $document, array $data, Request $request, int $ownerUserId): void
    {
        foreach (['title', 'category', 'file_type', 'description'] as $field) {
            if (array_key_exists($field, $data)) {
                $document->{$field} = $data[$field];
            }
        }

        if ($request->hasFile('file')) {
            self::deleteStoredFile($document->storage_path);
            $stored = self::storeUploadedFile($request, $ownerUserId);
            $document->storage_path = $stored['path'];
            $document->size_bytes = $stored['size'];
            $document->uploaded_at = now();
        }

        $document->save();
    }

    public static function fixturePath(): string
    {
        return database_path('fixtures/sample-medical-document.pdf');
    }

    /** Copy a demo fixture into the configured private storage disk. */
    public static function storeFixtureCopy(
        int $ownerUserId,
        string $title,
        string $fileType = 'pdf',
    ): array {
        $ext = match ($fileType) {
            'image' => 'jpg',
            'doc' => 'docx',
            default => 'pdf',
        };

        $slug = Str::slug(Str::limit($title, 40, '')) ?: 'document';
        $relative = 'documents/'.$ownerUserId.'/'.$slug.'-'.Str::random(8).'.'.$ext;
        $disk = Storage::disk(self::privateDiskName());

        if ($ext === 'pdf') {
            $source = self::fixturePath();
            if (! is_file($source)) {
                throw new \RuntimeException('Missing fixture: '.$source);
            }
            $disk->put($relative, file_get_contents($source));
        } else {
            // Minimal 1x1 PNG for image-type demo rows.
            $disk->put($relative, base64_decode(
                'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='
            ));
        }

        return ['path' => $relative, 'size' => $disk->size($relative)];
    }

    public static function privateDiskName(): string
    {
        return (string) config('mcare.private_disk', 'local');
    }

    public static function exists(?string $path): bool
    {
        if (! $path) {
            return false;
        }

        return Storage::disk(self::privateDiskName())->exists($path)
            || (self::privateDiskName() !== 'public' && Storage::disk('public')->exists($path));
    }

    public static function diskContaining(string $path): string
    {
        if (Storage::disk(self::privateDiskName())->exists($path)) {
            return self::privateDiskName();
        }

        return 'public';
    }
}
