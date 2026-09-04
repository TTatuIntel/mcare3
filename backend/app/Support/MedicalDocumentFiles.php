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
    /**
     * What a patient or clinician may put into the record.
     *
     * Previously `pdf,jpg,jpeg,png,doc,docx`, which is the set a web form
     * imagines and not the set a hospital produces. A photo taken on any
     * current iPhone is HEIC; a scanned result off a hospital MFP is TIFF; a
     * home-monitor export is CSV; discharge paperwork arrives as ODT or RTF as
     * often as DOCX. Every one of those was refused at the door, and a patient
     * standing at a reception desk being told their own X-ray is "not a
     * supported file" is the failure this list exists to prevent.
     *
     * @var list<string>
     */
    public const ALLOWED_EXTENSIONS = [
        'pdf',
        'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'heif', 'bmp', 'tif', 'tiff',
        'doc', 'docx', 'odt', 'rtf', 'txt',
        'xls', 'xlsx', 'csv',
        'html', 'htm',
    ];

    /**
     * The one extension-to-type table, used both to serve stored files and to
     * name generated ones.
     *
     * @var array<string, string>
     */
    private const EXTENSION_MIMES = [
        'pdf' => 'application/pdf',
        'jpg' => 'image/jpeg',
        'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'gif' => 'image/gif',
        'webp' => 'image/webp',
        'heic' => 'image/heic',
        'heif' => 'image/heif',
        'bmp' => 'image/bmp',
        'tif' => 'image/tiff',
        'tiff' => 'image/tiff',
        'doc' => 'application/msword',
        'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'odt' => 'application/vnd.oasis.opendocument.text',
        'rtf' => 'application/rtf',
        'txt' => 'text/plain',
        'xls' => 'application/vnd.ms-excel',
        'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'csv' => 'text/csv',
        'html' => 'text/html',
        'htm' => 'text/html',
    ];

    /** The `mimes:` rule body for a validator. */
    public static function allowedMimesRule(): string
    {
        return implode(',', self::ALLOWED_EXTENSIONS);
    }

    /**
     * Upload ceiling in kilobytes.
     *
     * 10 MB refused most of one MRI series and a good half of the scanned
     * multi-page results people are actually asked to bring in. Configurable so
     * a deployment on constrained storage can lower it without a code change.
     */
    public static function maxUploadKilobytes(): int
    {
        return (int) config('mcare.max_document_upload_kb', 25600);
    }

    public static function validateMeta(Request $request, bool $requireFile = false): array
    {
        return $request->validate([
            'title' => 'required|string|max:200',
            'category' => 'required|string|in:'.DocumentCategories::rule(),
            'file_type' => 'required|string|in:pdf,image,doc,other',
            'description' => 'nullable|string',
            'shared_with_doctor_id' => 'nullable|exists:users,id',
            'file' => ($requireFile ? 'required' : 'nullable')
                .'|file|max:'.self::maxUploadKilobytes()
                .'|mimes:'.self::allowedMimesRule(),
        ]);
    }

    public static function validateUpdate(Request $request): array
    {
        return $request->validate([
            'title' => 'sometimes|string|max:200',
            'category' => 'sometimes|string|in:'.DocumentCategories::rule(),
            'file_type' => 'sometimes|string|in:pdf,image,doc,other',
            'description' => 'nullable|string',
            'file' => 'nullable|file|max:'.self::maxUploadKilobytes()
                .'|mimes:'.self::allowedMimesRule(),
        ]);
    }

    /**
     * @return array{path: string, size: int, mime: string, original_name: string}
     */
    public static function storeUploadedFile(Request $request, int $ownerUserId): array
    {
        $f = $request->file('file');
        $path = $f->store('documents/'.$ownerUserId, self::privateDiskName());

        return [
            'path' => $path,
            'size' => $f->getSize(),
            // Read off the uploaded temp file rather than trusting the
            // browser's Content-Type header, which is client-supplied.
            'mime' => $f->getMimeType() ?: 'application/octet-stream',
            'original_name' => self::sanitizeFilename((string) $f->getClientOriginalName()),
        ];
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

    /**
     * Streams the stored file back.
     *
     * [$asAttachment] is what separates "open this" from "save this". Both were
     * `inline`, so Download did exactly what View did — opened a tab — and the
     * patient never got a file onto their device at all.
     */
    public static function stream(MedicalDocument $document, bool $asAttachment = false): StreamedResponse
    {
        $disk = Storage::disk(self::diskContaining($document->storage_path));

        $mime = self::mimeFor($document, $disk);
        $filename = $document->downloadName();
        $disposition = $asAttachment ? 'attachment' : 'inline';

        return response()->stream(function () use ($disk, $document) {
            $stream = $disk->readStream($document->storage_path);
            if ($stream !== false) {
                fpassthru($stream);
                fclose($stream);
            }
        }, 200, [
            'Content-Type' => $mime,
            'Content-Disposition' => $disposition.'; filename="'.$filename.'"',
            // The app reads the real name off the response so a share sheet
            // and a Downloads folder get what the server actually holds,
            // rather than a name inferred from a four-value enum. Exposed
            // because a cross-origin XHR cannot read it otherwise.
            'X-Document-Filename' => $filename,
            'Access-Control-Expose-Headers' => 'Content-Type, Content-Disposition, X-Document-Filename',
            'Cache-Control' => 'private, max-age=3600',
        ]);
    }

    /**
     * The content type to serve this document as.
     *
     * The recorded type wins — it was captured from the file itself. Rows
     * written before that column existed fall back to asking the disk, and only
     * then to the coarse `file_type` enum.
     */
    public static function mimeFor(MedicalDocument $document, mixed $disk = null): string
    {
        if (filled($document->mime_type)) {
            return (string) $document->mime_type;
        }

        if ($document->storage_path) {
            $disk ??= Storage::disk(self::diskContaining($document->storage_path));
            try {
                $detected = $disk->mimeType($document->storage_path);
            } catch (\Throwable) {
                $detected = null;
            }
            if (is_string($detected) && $detected !== '') {
                return $detected;
            }
        }

        return self::mimeForFileType($document->file_type);
    }

    /** Last-resort mapping for legacy rows that recorded nothing better. */
    public static function mimeForFileType(?string $fileType): string
    {
        return match ($fileType) {
            'pdf' => 'application/pdf',
            'image' => 'image/jpeg',
            'doc' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
            default => 'application/octet-stream',
        };
    }

    public static function mimeForExtension(string $extension): string
    {
        return self::EXTENSION_MIMES[strtolower($extension)] ?? 'application/octet-stream';
    }

    /** The extension conventionally used for a content type. */
    public static function extensionForMime(?string $mime): ?string
    {
        if (! $mime) {
            return null;
        }

        $bare = strtolower(trim(explode(';', $mime)[0]));
        $match = array_search($bare, self::EXTENSION_MIMES, true);

        return is_string($match) ? $match : null;
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
            $document->mime_type = $stored['mime'];
            $document->original_filename = $stored['original_name'];
            $document->uploaded_at = now();
        }

        $document->save();
    }

    public static function fixturePath(): string
    {
        return database_path('fixtures/sample-medical-document.pdf');
    }

    /**
     * Copy a demo fixture into the configured private storage disk.
     *
     * @return array{path: string, size: int, mime: string, original_name: string}
     */
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

        // The fixture is a PDF whatever the row calls itself, except in the
        // image case where a real PNG is written. Recording what was actually
        // put on disk keeps demo rows openable like any other.
        $writtenExt = $ext === 'pdf' ? 'pdf' : 'png';

        return [
            'path' => $relative,
            'size' => $disk->size($relative),
            'mime' => self::mimeForExtension($writtenExt),
            'original_name' => $slug.'.'.$writtenExt,
        ];
    }

    /**
     * Writes content the server generated — as opposed to a file someone
     * uploaded — into the same private store, and returns the same shape the
     * upload path returns so callers can treat both alike.
     *
     * The mime travels with it. An issued report is HTML, and storing it with
     * no recorded type is what left patients holding a `.bin` their phone
     * refused to open.
     *
     * @return array{path: string, size: int, mime: string, original_name: string}
     */
    public static function storeGeneratedFile(
        int $ownerUserId,
        string $title,
        string $contents,
        string $extension = 'html',
    ): array {
        $slug = Str::slug(Str::limit($title, 40, '')) ?: 'document';
        $relative = 'documents/'.$ownerUserId.'/'.$slug.'-'.Str::random(8).'.'.$extension;

        $disk = Storage::disk(self::privateDiskName());
        $disk->put($relative, $contents);

        return [
            'path' => $relative,
            'size' => $disk->size($relative),
            'mime' => self::mimeForExtension($extension),
            'original_name' => $slug.'.'.$extension,
        ];
    }

    /**
     * Strips everything a filename could smuggle: directory separators, control
     * characters and quotes, and leading dots. What reaches a
     * Content-Disposition header and a patient's Downloads folder should be a
     * name and nothing else.
     */
    public static function sanitizeFilename(string $name): string
    {
        $name = basename(str_replace('\\', '/', $name));
        $name = preg_replace('/[\x00-\x1F\x7F";\\\\]+/u', '', $name) ?? '';
        $name = ltrim(trim($name), '.');

        return $name === '' ? 'document' : (string) Str::limit($name, 120, '');
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
