<?php

namespace App\Http\Controllers\Api\V1\Admin;

use App\Http\Controllers\Controller;
use App\Models\SupportTicket;
use App\Models\SupportTicketReply;
use App\Models\User;
use App\Services\AuditService;
use App\Services\WorkflowNotificationService;
use App\Support\ApiResponse;
use Illuminate\Http\Request;

class SupportTicketsController extends Controller
{
    use ApiResponse;

    public function __construct(private readonly AuditService $audit) {}

    public function index(Request $request)
    {
        $status = $request->query('status');
        $query = SupportTicket::query()
            ->with(['user', 'assignee'])
            ->orderByDesc('created_at');
        if ($status) {
            $query->where('status', $status);
        }
        $tickets = $query->limit(200)->get()->map(
            fn (SupportTicket $t) => $this->ticketPayload($t),
        );

        return $this->success(['tickets' => $tickets]);
    }

    public function reply(Request $request, SupportTicket $ticket)
    {
        $data = $request->validate([
            'body' => 'required|string|max:4000',
        ]);

        $actor = $request->user();
        $reply = SupportTicketReply::create([
            'ticket_id' => $ticket->id,
            'author_user_id' => $actor->id,
            'author' => $actor->fullName(),
            'is_staff' => true,
            'body' => $data['body'],
            'sent_at' => now(),
        ]);

        $ticket->update([
            'status' => $ticket->status === 'open' ? 'inProgress' : $ticket->status,
            'updated_at_app' => now(),
            'assigned_to' => $ticket->assigned_to ?? $actor->id,
        ]);
        WorkflowNotificationService::staffRepliedToSupport($ticket, $actor);

        $this->audit->record(
            $actor,
            'support.replied',
            $ticket->subject,
            'activity',
            ['ticket_id' => $ticket->id, 'reply_id' => $reply->id],
        );

        return $this->success(
            ['ticket' => $this->ticketPayload($ticket->fresh())],
            'Reply sent.',
        );
    }

    public function assign(Request $request, SupportTicket $ticket)
    {
        $data = $request->validate([
            'assignee_id' => 'nullable|integer|exists:users,id',
        ]);

        $assigneeId = $data['assignee_id'] ?? null;

        if ($assigneeId !== null) {
            $assignee = User::query()->findOrFail($assigneeId);
            if (! in_array($assignee->role, ['admin', 'mcare_assistant'], true)) {
                return $this->error('Assignee must be admin or mCare assistant staff.', 422);
            }
            if ($assignee->approval_status !== 'active') {
                return $this->error('Assignee account is not active.', 422);
            }
        }

        $updates = [
            'assigned_to' => $assigneeId,
            'updated_at_app' => now(),
        ];
        if ($assigneeId !== null && $ticket->status === 'open') {
            $updates['status'] = 'inProgress';
        }

        $ticket->update($updates);

        $this->audit->record(
            $request->user(),
            'support.assigned',
            $ticket->subject,
            'activity',
            [
                'ticket_id' => $ticket->id,
                'assignee_id' => $assigneeId,
            ],
        );

        return $this->success(
            ['ticket' => $this->ticketPayload($ticket->fresh())],
            $assigneeId ? 'Ticket assigned.' : 'Ticket unassigned.',
        );
    }

    public function resolve(Request $request, SupportTicket $ticket)
    {
        $ticket->update([
            'status' => 'resolved',
            'updated_at_app' => now(),
            'assigned_to' => $ticket->assigned_to ?? $request->user()->id,
        ]);
        WorkflowNotificationService::supportStatusChanged($ticket, 'resolved');

        $this->audit->record(
            $request->user(),
            'support.resolved',
            $ticket->subject,
            'activity',
            ['ticket_id' => $ticket->id],
        );

        return $this->success(
            ['ticket' => $this->ticketPayload($ticket->fresh())],
            'Marked resolved.',
        );
    }

    public function close(Request $request, SupportTicket $ticket)
    {
        $ticket->update([
            'status' => 'closed',
            'updated_at_app' => now(),
        ]);
        WorkflowNotificationService::supportStatusChanged($ticket, 'closed');

        $this->audit->record(
            $request->user(),
            'support.closed',
            $ticket->subject,
            'activity',
            ['ticket_id' => $ticket->id],
        );

        return $this->success(
            ['ticket' => $this->ticketPayload($ticket->fresh())],
            'Closed.',
        );
    }

    public function reopen(Request $request, SupportTicket $ticket)
    {
        $ticket->update([
            'status' => 'open',
            'updated_at_app' => now(),
        ]);
        WorkflowNotificationService::supportStatusChanged($ticket, 'open');

        $this->audit->record(
            $request->user(),
            'support.reopened',
            $ticket->subject,
            'activity',
            ['ticket_id' => $ticket->id],
        );

        return $this->success(
            ['ticket' => $this->ticketPayload($ticket->fresh())],
            'Ticket reopened.',
        );
    }

    private function ticketPayload(SupportTicket $ticket): array
    {
        $ticket->loadMissing(['user', 'assignee', 'replies']);

        $arr = $ticket->toApiArray();
        $arr['patient_name'] = $ticket->user?->fullName();
        $arr['patient_user_id'] = (string) $ticket->user_id;
        $arr['assigned_to_name'] = $ticket->assignee?->fullName();

        return $arr;
    }
}
