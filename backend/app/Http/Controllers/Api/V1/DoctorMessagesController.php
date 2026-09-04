<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\ChatMessage;
use App\Models\Conversation;
use App\Models\User;
use App\Services\RealtimeSignalService;
use App\Support\ApiResponse;
use Illuminate\Http\Request;

class DoctorMessagesController extends Controller
{
    use ApiResponse;

    public function index(Request $request)
    {
        $doctor = $request->user();
        $caseloadIds = DoctorAccess::caseloadPatientIds($doctor);

        $conversations = Conversation::query()
            ->where(function ($q) use ($doctor) {
                $q->where('participant_user_id', $doctor->id)
                    ->orWhere('user_id', $doctor->id);
            })
            ->where(function ($q) use ($doctor, $caseloadIds) {
                $q->where('user_id', $doctor->id)
                    ->orWhereIn('user_id', $caseloadIds)
                    ->orWhereHas('user', fn ($owner) => $owner->where('role', '!=', 'patient'));
            })
            ->with(['user', 'participant', 'messages' => fn ($q) => $q->latest('sent_at')->limit(1)])
            ->withCount(['messages as unread_messages_count' => fn ($q) => $q
                ->where('sender_user_id', '!=', $doctor->id)
                ->where('read', false)])
            ->withMax('messages', 'sent_at')
            ->orderByDesc('messages_max_sent_at')
            ->limit(200)
            ->get();

        return $this->success([
            'conversations' => $conversations->map(
                fn (Conversation $c) => $this->conversationForDoctor($c, $doctor)
            )->all(),
        ]);
    }

    public function thread(Request $request, Conversation $conversation)
    {
        $this->assertDoctorCanAccess($request->user(), $conversation);

        $messages = $conversation->messages()->orderBy('sent_at')->get();
        $conversation->setRelation('messages', $messages);

        return $this->success([
            'conversation' => $this->conversationForDoctor($conversation, $request->user()),
            'messages' => $messages->map->toApiArray()->all(),
        ]);
    }

    public function send(Request $request, Conversation $conversation)
    {
        $doctor = $request->user();
        $this->assertDoctorCanAccess($doctor, $conversation);

        $data = $request->validate([
            'body' => 'required|string',
        ]);

        $msg = ChatMessage::create([
            'conversation_id' => $conversation->id,
            'sender_user_id' => $doctor->id,
            'body' => $data['body'],
            'read' => false,
            'sent_at' => now(),
        ]);

        DoctorAccess::audit(
            $doctor,
            'Sent message',
            optional($conversation->user)->fullName() ?? 'patient',
            'messages'
        );

        return $this->success(['message' => $msg->toApiArray()], 'Message sent.', 201);
    }

    public function markRead(Request $request, Conversation $conversation)
    {
        $this->assertDoctorCanAccess($request->user(), $conversation);

        $conversation->messages()
            ->where('sender_user_id', '!=', $request->user()->id)
            ->where('read', false)
            ->update(['read' => true]);
        RealtimeSignalService::forModel($conversation, 'updated', ['messages']);

        return $this->success(null, 'Marked read.');
    }

    private function assertDoctorCanAccess($doctor, Conversation $conversation): void
    {
        $caseloadIds = DoctorAccess::caseloadPatientIds($doctor);
        $directParticipant = $conversation->participant_user_id === $doctor->id
            || $conversation->user_id === $doctor->id;
        $ownerRole = $conversation->relationLoaded('user')
            ? $conversation->user?->role
            : $conversation->user()->value('role');
        $allowedOwner = $conversation->user_id === $doctor->id
            || $ownerRole !== 'patient'
            || in_array($conversation->user_id, $caseloadIds, true);
        $allowed = $directParticipant && $allowedOwner;
        abort_unless($allowed, 403, 'Conversation not in your caseload.');
    }

    private function conversationForDoctor(Conversation $c, User $doctor): array
    {
        $owner = $c->relationLoaded('user') ? $c->user : $c->user()->first();
        $participant = $c->relationLoaded('participant')
            ? $c->participant
            : $c->participant()->first();
        $counterparty = (int) $c->user_id === (int) $doctor->id
            ? $participant
            : $owner;
        $base = $c->toApiArray($doctor);

        return array_merge($base, [
            'patient_id' => $counterparty?->role === 'patient'
                ? (string) $counterparty->id
                : null,
            'patient_name' => $counterparty?->fullName() ?? '',
            'participant' => [
                'id' => $counterparty ? (string) $counterparty->id : '',
                'name' => $counterparty?->fullName() ?? $c->participant_name,
                'role' => $counterparty?->role ?? $c->participant_role,
                'specialty' => $counterparty?->specialty ?? $c->participant_specialty,
            ],
        ]);
    }
}
