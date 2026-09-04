<?php

namespace App\Http\Controllers\Api\V1\Admin;

use App\Http\Controllers\Concerns\ManagesVitalReportQueue;
use App\Http\Controllers\Controller;
use App\Models\VitalReportRequest;
use App\Services\AuditService;
use App\Support\ApiResponse;
use Illuminate\Http\Request;

/**
 * The admin and mCare-assistant side of the vital report queue.
 *
 * The queue has always escalated on its own — doctor for 48 hours, then
 * assistant, then admin — and until now it escalated into nothing. Those tiers
 * had no claim route, no fulfil route and no screen, so a request that aged
 * past its first window was handed to people who could not act on it. The
 * patient went on waiting for a report that no one was able to produce, and the
 * request sat at the top of a queue as the oldest thing in it forever.
 *
 * Same rules as the doctor side, from {@see ManagesVitalReportQueue}: claim
 * before you finish it, one holder at a time, every act on the trail the
 * patient reads. Two things differ, and both follow from admin staff not
 * having a caseload — which is the whole reason the queue escalates to them.
 * They see the queue entire rather than a slice of it, and the route's
 * permission middleware is the gate that a caseload check is on the doctor
 * side.
 */
class VitalReportRequestsController extends Controller
{
    use ApiResponse;
    use ManagesVitalReportQueue;

    public function __construct(private readonly AuditService $audit) {}

    /**
     * Admin staff are not on a caseload; the route's permission middleware is
     * the gate, and re-checking here would refuse every legitimate caller.
     */
    protected function assertQueueAccess(Request $request, VitalReportRequest $vitalReportRequest): void
    {
        // Intentionally empty — see the class docblock.
    }

    /**
     * The whole queue. An escalated request is by definition one no caseload
     * answered, so narrowing by caseload would hide exactly the requests these
     * tiers exist to pick up.
     *
     * @return list<int>|null
     */
    protected function queueScopedPatientIds(Request $request): ?array
    {
        return null;
    }

    /**
     * Patients read this as "who is preparing my report", so it says the role
     * as well as the name — "mCare team · Nia Chebet" answers a different
     * question from a bare name when the report is not coming from their
     * doctor.
     */
    protected function queueActorLabel(Request $request): string
    {
        $user = $request->user();
        $role = $user->role === 'mcare_assistant' ? 'mCare team' : 'mCare admin';

        return $role.' · '.$user->fullName();
    }

    protected function recordQueueAudit(Request $request, string $action, string $detail): void
    {
        $this->audit->record($request->user(), $action, $detail, 'activity');
    }
}
