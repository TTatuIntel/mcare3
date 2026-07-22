<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\ChatMessage;
use App\Models\Conversation;
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
            ->where(function ($q) use ($doctor, $caseloadIds) {
                $q->where('participant_user_id', $doctor->id);
                if ($caseloadIds) {
                    $q->orWhereIn('user_id', $caseloadIds);
                }
            })
            ->with(['user', 'messages' => fn ($q) => $q->latest('sent_at')->limit(1)])
            ->orderByDesc('last_message_at')
            ->limit(200)
            ->get();

        return $this->success([
            'conversations' => $conversations->map(
                fn (Conversation $c) => $this->conversationForDoctor($c, $doctor->id)
            )->all(),
        ]);
    }

    public function thread(Request $request, Conversation $conversation)
    {
        $this->assertDoctorCanAccess($request->user(), $conversation);

        return $this->success([
            'conversation' => $this->conversationForDoctor($conversation, $request->user()->id),
            'messages' => $conversation->messages()
                ->orderBy('sent_at')
                ->get()
                ->map->toApiArray()
                ->all(),
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
            'read' => true,
            'sent_at' => now(),
        ]);
        $conversation->update(['last_message_at' => $msg->sent_at]);

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
        $conversation->update(['unread_count' => 0]);

        return $this->success(null, 'Marked read.');
    }

    private function assertDoctorCanAccess($doctor, Conversation $conversation): void
    {
        $caseloadIds = DoctorAccess::caseloadPatientIds($doctor);
        $allowed = $conversation->participant_user_id === $doctor->id
            || in_array($conversation->user_id, $caseloadIds, true);
        abort_unless($allowed, 403, 'Conversation not in your caseload.');
    }

    private function conversationForDoctor(Conversation $c, int $doctorId): array
    {
        $patient = $c->user;
        $last = $c->messages->first()
            ?? $c->messages()->latest('sent_at')->first();

        return [
            'id' => (string) $c->id,
            'patient_id' => (string) $c->user_id,
            'patient_name' => $patient ? $patient->fullName() : '',
            'participant' => [
                'id' => (string) $c->user_id,
                'name' => $patient ? $patient->fullName() : ($c->participant_name ?? 'Patient'),
                'role' => 'patient',
                'specialty' => null,
            ],
            'last_message' => $last?->toApiArray(),
            'unread_count' => $c->unread_count,
        ];
    }
}
