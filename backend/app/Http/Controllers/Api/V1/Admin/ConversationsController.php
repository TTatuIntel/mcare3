<?php

namespace App\Http\Controllers\Api\V1\Admin;

use App\Http\Controllers\Controller;
use App\Models\CareProvider;
use App\Models\ChatMessage;
use App\Models\Conversation;
use App\Models\User;
use App\Services\RealtimeSignalService;
use App\Support\ApiResponse;
use Illuminate\Http\Request;

/**
 * Admin / assistant inbox. Conversations where the staff user is the
 * counterparty (participant_user_id = me) OR the patient owner is the
 * staff user.
 */
class ConversationsController extends Controller
{
    use ApiResponse;

    public function index(Request $request)
    {
        $me = $request->user();

        $query = Conversation::query()
            ->with(['user', 'participant', 'messages' => fn ($q) => $q->latest('sent_at')->limit(1)])
            ->withCount(['messages as unread_messages_count' => fn ($q) => $q
                ->where('sender_user_id', '!=', $me->id)
                ->where('read', false)])
            ->withMax('messages', 'sent_at')
            ->orderByDesc('messages_max_sent_at')
            ->limit(200);

        // Assistants only see conversations they are a direct participant of;
        // admins see all conversations for full oversight.
        if ($me->role !== 'admin') {
            $query->where(function ($q) use ($me) {
                $q->where('participant_user_id', $me->id)
                    ->orWhere('user_id', $me->id);
            });
        }

        $conversations = $query->get()->map(fn (Conversation $c) => $c->toApiArray($me));

        return $this->success(['conversations' => $conversations]);
    }

    public function store(Request $request)
    {
        $me = $request->user();
        if (! in_array($me->role, ['admin', 'mcare_assistant'], true)) {
            abort(403);
        }

        $data = $request->validate([
            'user_id' => 'required|exists:users,id',
        ]);

        $target = User::findOrFail($data['user_id']);
        if ((string) $target->id === (string) $me->id) {
            return $this->error('Cannot start a conversation with yourself.', 422);
        }

        if ($target->role === 'patient') {
            $conversation = Conversation::firstOrCreate(
                [
                    'user_id' => $target->id,
                    'participant_user_id' => $me->id,
                ],
                [
                    'participant_name' => $me->fullName(),
                    'participant_role' => $me->role,
                    'participant_specialty' => null,
                ],
            );
        } else {
            $provider = CareProvider::where('user_id', $target->id)->first();
            $conversation = Conversation::firstOrCreate(
                [
                    'user_id' => $me->id,
                    'participant_user_id' => $target->id,
                ],
                [
                    'participant_name' => $target->fullName(),
                    'participant_role' => $target->role,
                    'participant_specialty' => $provider?->specialty,
                ],
            );
        }

        return $this->success(
            ['conversation' => $conversation->fresh()->toApiArray($me)],
            'Conversation ready.',
            201,
        );
    }

    public function thread(Request $request, Conversation $conversation)
    {
        $this->ensureCanView($request, $conversation);

        $messages = $conversation->messages()->orderBy('sent_at')->get()
            ->map(fn (ChatMessage $m) => $m->toApiArray());

        return $this->success(['messages' => $messages]);
    }

    public function send(Request $request, Conversation $conversation)
    {
        $this->ensureDirectParticipant($request, $conversation);

        $data = $request->validate([
            'body' => 'required|string|max:4000',
        ]);

        $message = ChatMessage::create([
            'conversation_id' => $conversation->id,
            'sender_user_id' => $request->user()->id,
            'body' => $data['body'],
            'read' => false,
            'sent_at' => now(),
        ]);

        return $this->success(['message' => $message->toApiArray()], 'Sent.', 201);
    }

    public function markRead(Request $request, Conversation $conversation)
    {
        $this->ensureDirectParticipant($request, $conversation);

        $conversation->messages()
            ->where('sender_user_id', '!=', $request->user()->id)
            ->where('read', false)
            ->update(['read' => true]);

        RealtimeSignalService::forModel($conversation, 'updated', ['messages']);

        return $this->success(['conversation_id' => (string) $conversation->id], 'Marked read.');
    }

    private function ensureCanView(Request $request, Conversation $conversation): void
    {
        $me = $request->user();
        if ($me->role === 'admin') {
            return;
        }
        $this->ensureDirectParticipant($request, $conversation);
    }

    private function ensureDirectParticipant(Request $request, Conversation $conversation): void
    {
        $me = $request->user();
        if ($conversation->participant_user_id !== $me->id && $conversation->user_id !== $me->id) {
            abort(response()->json([
                'success' => false,
                'message' => 'Not a conversation participant.',
                'data' => null,
            ], 403));
        }
    }
}
