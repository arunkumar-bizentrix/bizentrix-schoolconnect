import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../shared/widgets/list_state_views.dart';
import '../../exams/screens/exams_screen.dart';
import '../providers/messages_provider.dart';

/// One conversation. Opened with a [conversationId], or with a [recipient]
/// when nothing has been said yet - the first message creates the thread.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required int this.conversationId}) : recipient = null;

  const ChatScreen.newConversation({super.key, required MessageContact this.recipient}) : conversationId = null;

  final int? conversationId;
  final MessageContact? recipient;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _composer = TextEditingController();
  int? _conversationId;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _conversationId = widget.conversationId;
  }

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _composer.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);

    final actions = ref.read(messageActionsProvider);
    String? error;
    if (_conversationId == null) {
      final (id, startError) = await actions.start(widget.recipient!.id, body);
      error = startError;
      if (id != null && mounted) setState(() => _conversationId = id);
    } else {
      error = await actions.send(_conversationId!, body);
    }

    if (!mounted) return;
    setState(() => _sending = false);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error), backgroundColor: AppColors.statusOverdueText));
      return;
    }
    _composer.clear();
  }

  @override
  Widget build(BuildContext context) {
    final threadAsync = _conversationId == null ? null : ref.watch(chatThreadProvider(_conversationId!));
    final other = threadAsync?.value?.other ?? widget.recipient;
    final canReply = threadAsync?.value?.canReply ?? true;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(other?.fullName ?? 'Conversation',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.textPrimary)),
            if (other != null && other.context.isNotEmpty)
              Text(other.context, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: threadAsync == null
                ? const EmptyState(icon: Icons.chat_bubble_outline, title: 'Say hello',
                    message: 'Your first message starts the conversation.')
                : threadAsync.when(
                    loading: () => const LoadingView(),
                    error: (error, _) => ErrorStateView(message: friendlyError(ref, error),
                        onRetry: () => ref.invalidate(chatThreadProvider(_conversationId!))),
                    data: (thread) => ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                      itemCount: thread.messages.length,
                      itemBuilder: (context, index) => _Bubble(message: thread.messages[thread.messages.length - 1 - index]),
                    ),
                  ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: AppColors.border))),
              child: canReply
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _composer,
                            minLines: 1,
                            maxLines: 5,
                            maxLength: 2000,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: InputDecoration(
                              hintText: 'Write a message',
                              counterText: '',
                              isDense: true,
                              filled: true,
                              fillColor: AppColors.background,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton.filled(
                          tooltip: 'Send',
                          onPressed: _sending ? null : _send,
                          style: IconButton.styleFrom(backgroundColor: AppColors.primary),
                          icon: _sending
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.send_rounded, color: Colors.white),
                        ),
                      ],
                    )
                  : const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text(
                        'You can no longer reply here - this person is not connected to your classes any more.',
                        style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final mine = message.isMine;
    final time = message.createdAt;
    final stamp = time == null
        ? ''
        : '${time.hour % 12 == 0 ? 12 : time.hour % 12}:${time.minute.toString().padLeft(2, '0')} ${time.hour < 12 ? 'AM' : 'PM'}';

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          decoration: BoxDecoration(
            color: mine ? AppColors.primary : Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(mine ? 16 : 4),
              bottomRight: Radius.circular(mine ? 4 : 16),
            ),
            border: mine ? null : Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: SelectableText(message.body,
                    style: TextStyle(fontSize: 14, height: 1.35, color: mine ? Colors.white : AppColors.textPrimary)),
              ),
              const SizedBox(height: 2),
              Text(
                mine && message.readAt != null ? '$stamp · Read' : stamp,
                style: TextStyle(fontSize: 10.5, color: mine ? Colors.white70 : AppColors.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
