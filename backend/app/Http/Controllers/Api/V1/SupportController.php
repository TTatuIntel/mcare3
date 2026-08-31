<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\SupportTicket;
use App\Models\SupportTicketReply;
use App\Services\WorkflowNotificationService;
use App\Support\ApiResponse;
use Illuminate\Http\Request;

class SupportController extends Controller
{
    use ApiResponse;

    public function store(Request $request)
    {
        $data = $request->validate([
            'subject' => 'required|string|max:160',
            'description' => 'required|string',
            'category' => 'required|string|in:technical,medical,billing,account,other',
            'priority' => 'nullable|string|in:low,normal,high,urgent',
        ]);

        $ticket = $request->user()->supportTickets()->create([
            'subject' => $data['subject'],
            'description' => $data['description'],
            'category' => $data['category'],
            'priority' => $data['priority'] ?? 'normal',
            'status' => 'open',
            'updated_at_app' => now(),
        ]);
        WorkflowNotificationService::supportTicketOpened($ticket, $request->user());

        return $this->success(['ticket' => $ticket->toApiArray()], 'Ticket opened.', 201);
    }

    public function reply(Request $request, SupportTicket $ticket)
    {
        abort_unless($ticket->user_id === $request->user()->id, 403);
        $data = $request->validate(['body' => 'required|string']);
        $reply = SupportTicketReply::create([
            'ticket_id' => $ticket->id,
            'author_user_id' => $request->user()->id,
            'author' => $request->user()->fullName(),
            'is_staff' => false,
            'body' => $data['body'],
            'sent_at' => now(),
        ]);
        $ticket->update(['updated_at_app' => now()]);
        WorkflowNotificationService::patientRepliedToSupport($ticket, $request->user());

        return $this->success(['reply' => $reply->toApiArray()], 'Reply sent.', 201);
    }

    public function close(Request $request, SupportTicket $ticket)
    {
        abort_unless($ticket->user_id === $request->user()->id, 403);
        $ticket->update(['status' => 'closed', 'updated_at_app' => now()]);
        return $this->success(['ticket' => $ticket->fresh()->toApiArray()], 'Ticket closed.');
    }
}
