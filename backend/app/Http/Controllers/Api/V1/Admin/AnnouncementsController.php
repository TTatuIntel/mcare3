<?php

namespace App\Http\Controllers\Api\V1\Admin;

use App\Http\Controllers\Controller;
use App\Models\Announcement;
use App\Services\AuditService;
use App\Support\ApiResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class AnnouncementsController extends Controller
{
    use ApiResponse;

    public function __construct(private readonly AuditService $audit) {}

    public function index(Request $request)
    {
        $query = Announcement::query()->orderByDesc('created_at');

        if ($audience = $request->query('audience')) {
            $query->where('audience', $audience);
        }
        $published = $request->query('published');
        if ($published !== null && $published !== '') {
            $query->where('is_published', filter_var($published, FILTER_VALIDATE_BOOL));
        }

        $list = $query->limit(200)->get()->map(fn (Announcement $a) => $a->toApiArray());
        return $this->success(['announcements' => $list]);
    }

    public function store(Request $request)
    {
        $data = $this->validatePayload($request);

        $a = Announcement::create([
            ...$data,
            'created_by_user_id' => $request->user()->id,
            'is_published' => false,
        ]);

        $this->audit->record(
            $request->user(),
            'announcement.created',
            $a->title,
            'activity',
            ['announcement_id' => $a->id],
        );

        return $this->success(['announcement' => $a->toApiArray()], 'Created.', 201);
    }

    public function update(Request $request, Announcement $announcement)
    {
        $data = $this->validatePayload($request);
        $announcement->update($data);

        $this->audit->record(
            $request->user(),
            'announcement.updated',
            $announcement->title,
            'activity',
            ['announcement_id' => $announcement->id],
        );

        return $this->success(['announcement' => $announcement->fresh()->toApiArray()], 'Updated.');
    }

    public function publish(Request $request, Announcement $announcement)
    {
        $data = $request->validate([
            'publish' => 'required|boolean',
        ]);

        $announcement->update(['is_published' => $data['publish']]);

        $this->audit->record(
            $request->user(),
            $data['publish'] ? 'announcement.published' : 'announcement.unpublished',
            $announcement->title,
            'activity',
            ['announcement_id' => $announcement->id],
        );

        return $this->success(['announcement' => $announcement->fresh()->toApiArray()], 'Saved.');
    }

    public function destroy(Request $request, Announcement $announcement)
    {
        $title = $announcement->title;
        $id = $announcement->id;
        $announcement->delete();

        $this->audit->record(
            $request->user(),
            'announcement.deleted',
            $title,
            'activity',
            ['announcement_id' => $id],
        );

        return $this->success(['id' => (string) $id], 'Deleted.');
    }

    private function validatePayload(Request $request): array
    {
        return $request->validate([
            'title' => 'required|string|max:160',
            'body' => 'required|string|max:4000',
            'audience' => ['required', Rule::in(Announcement::AUDIENCES)],
            'cta_label' => 'nullable|string|max:64',
            'cta_url' => 'nullable|url|max:512',
            'image_path' => 'nullable|string|max:512',
            'starts_at' => 'nullable|date',
            'ends_at' => 'nullable|date|after_or_equal:starts_at',
        ]);
    }
}
