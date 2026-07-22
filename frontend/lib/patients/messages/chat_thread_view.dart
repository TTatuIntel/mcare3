import 'package:flutter/material.dart';

import '../../shared/constants/route_names.dart';
import '../../shared/state/messages_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_message_bubble.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/patient_scaffold.dart';

class ChatThreadView extends StatefulWidget {
  const ChatThreadView({super.key, required this.conversationId});
  final String conversationId;

  @override
  State<ChatThreadView> createState() => _ChatThreadViewState();
}

class _ChatThreadViewState extends State<ChatThreadView> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      MessagesState.instance.loadThread(widget.conversationId);
      MessagesState.instance.markRead(widget.conversationId);
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    MessagesState.instance.send(widget.conversationId, text);
    _input.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: MessagesState.instance,
      builder: (context, _) {
        final convo = MessagesState.instance.byId(widget.conversationId);
        if (convo == null) {
          return PatientScaffold(
            currentRoute: '',
            detachedNav: true,
            scrollable: false,
            title: 'Chat',
            body: EmptyStateView(
              icon: AppIcons.chat,
              title: 'Conversation not found',
              message: 'This thread could not be loaded.',
            ),
          );
        }

        final messages = MessagesState.instance.thread(widget.conversationId);

        return PatientScaffold(
          currentRoute: RouteNames.patientMessages,
          detachedNav: true,
          scrollable: false,
          title: convo.participant.name,
          subtitle: convo.participant.specialty ?? 'Care team',
          body: Column(
            children: [
              Expanded(
                child: messages.isEmpty
                    ? Center(
                        child: EmptyStateView(
                          icon: AppIcons.chat,
                          title: 'No messages yet',
                          message: 'Send a message to start the conversation.',
                          compact: true,
                        ),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.only(
                          top: AppSpacing.sm,
                          bottom: AppSpacing.lg,
                        ),
                        itemCount: messages.length,
                        itemBuilder: (_, i) {
                          final m = messages[i];
                          return AppMessageBubble(
                            body: m.body,
                            sentAt: m.sentAt,
                            isMine: m.senderId == 'me',
                            author: m.senderId == 'me'
                                ? null
                                : convo.participant.name,
                          );
                        },
                      ),
              ),
              _Composer(controller: _input, onSend: _send),
            ],
          ),
        );
      },
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.onSend});
  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppPalette.border(context))),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              style: theme.textTheme.bodyMedium,
              decoration: InputDecoration(
                hintText: 'Type a message…',
                hintStyle: theme.textTheme.bodyMedium?.copyWith(
                  color: AppPalette.textMuted(context),
                ),
                filled: true,
                fillColor: AppPalette.surfaceAlt(context),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm,
                ),
              ),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          AppButton.icon(
            icon: AppIcons.chat,
            semanticLabel: 'Send',
            onPressed: onSend,
          ),
        ],
      ),
    );
  }
}
