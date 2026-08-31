<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\ChatMessage;
use App\Models\Conversation;
use App\Services\RealtimeSignalService;
use App\Services\WorkflowNotificationService;
use App\Support\ApiResponse;
use Illuminate\Http\Request;

class MessagesController extends Controller
{
    use ApiResponse;

    public function thread(Request $request, Conversation $conversation)
    {
        abort_unless($conversation->user_id === $request->user()->id, 403);
        $messages = $conversation->messages()
            ->orderBy('sent_at')
            ->get();
        $conversation->setRelation('messages', $messages);

        return $this->success([
            'conversation' => $conversation->toApiArray($request->user()),
            'messages' => $messages->map->toApiArray()->all(),
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
            'read' => false,
            'sent_at' => now(),
        ]);
        WorkflowNotificationService::messageSent($msg, $conversation, $request->user());

        return $this->success(['message' => $msg->toApiArray()], 'Message sent.', 201);
    }

    public function markRead(Request $request, Conversation $conversation)
    {
        abort_unless($conversation->user_id === $request->user()->id, 403);
        $conversation->messages()
            ->where('sender_user_id', '!=', $request->user()->id)
            ->where('read', false)
            ->update(['read' => true]);
        WorkflowNotificationService::markConversationRead($request->user(), $conversation);
        RealtimeSignalService::forModel($conversation, 'updated', ['messages']);

        return $this->success(null, 'Marked read.');
    }
}
