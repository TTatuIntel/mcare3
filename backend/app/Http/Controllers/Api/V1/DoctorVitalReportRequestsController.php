<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Concerns\ManagesVitalReportQueue;
use App\Http\Controllers\Controller;
use App\Models\VitalReportRequest;
use App\Support\ApiResponse;
use Illuminate\Http\Request;

/**
 * The doctor's view of the shared vital report queue.
 *
 * Every clinician on the patient's caseload sees every request — that is
 * deliberate, and it is what makes cover possible when one of them is away.
 * What was missing was ownership: two doctors could open the same request and
 * both write the report, and a request nobody had started looked identical to
 * one being worked on right now.
 *
 * So the queue is shared and the work is not. A request must be claimed before
 * it can be finished, exactly one clinician can hold it, and every claim,
 * release and resolution is written to the request's own trail — which the
 * patient reads too.
 *
 * The behaviour lives in {@see ManagesVitalReportQueue}, shared with the admin
 * tiers the queue escalates to. This class supplies only what is specific to a
 * doctor: the caseload gate and the name the patient reads.
 */
class DoctorVitalReportRequestsController extends Controller
{
    use ApiResponse;
    use ManagesVitalReportQueue;

    protected function assertQueueAccess(Request $request, VitalReportRequest $vitalReportRequest): void
    {
        DoctorAccess::assertCaseload($request->user(), $vitalReportRequest->user_id);
    }

    /** @return list<int>|null */
    protected function queueScopedPatientIds(Request $request): ?array
    {
        return DoctorAccess::caseloadPatientIds($request->user());
    }

    protected function queueActorLabel(Request $request): string
    {
        return 'Dr. '.$request->user()->fullName();
    }

    protected function recordQueueAudit(Request $request, string $action, string $detail): void
    {
        DoctorAccess::audit($request->user(), $action, $detail);
    }
}
