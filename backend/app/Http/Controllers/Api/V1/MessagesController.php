<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\ChatMessage;
use App\Models\Conversation;
use App\Support\ApiResponse;
use Illuminate\Http\Request;

class MessagesController extends Controller
{
    use ApiResponse;

    public function thread(Request $request, Conversation $conversation)
    {
        abort_unless($conversation->user_id === $request->user()->id, 403);
        return $this->success([
            'conversation' => $conversation->toApiArray(),
            'messages' => $conversation->messages()
                ->orderBy('sent_at')
                ->get()
                ->map->toApiArray()
                ->all(),
        ]);
    }

    public function send(Request $request, Conversation $conversation)
    {
        abort_unless($conversation->user_id === $request->user()->id, 403);
        $data = $request->validate([
            'body' => 'required|string',
        ]);
        $msg = ChatMessage::create([
            'conversation_id' => $conversation->id,
            'sender_user_id' => $request->user()->id,
            'body' => $data['body'],
            'read' => true,
            'sent_at' => now(),
        ]);
        $conversation->update(['last_message_at' => $msg->sent_at]);
        return $this->success(['message' => $msg->toApiArray()], 'Message sent.', 201);
    }

    public function markRead(Request $request, Conversation $conversation)
    {
        abort_unless($conversation->user_id === $request->user()->id, 403);
        $conversation->messages()->where('read', false)->update(['read' => true]);
        $conversation->update(['unread_count' => 0]);
        return $this->success(null, 'Marked read.');
    }
}
