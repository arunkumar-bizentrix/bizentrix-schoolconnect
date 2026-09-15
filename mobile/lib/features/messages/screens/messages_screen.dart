import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../shared/widgets/list_state_views.dart';
import '../../../shared/widgets/search_field.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../exams/screens/exams_screen.dart';
import '../providers/messages_provider.dart';
import 'chat_screen.dart';

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  return parts.length == 1 ? parts.first[0].toUpperCase() : (parts.first[0] + parts.last[0]).toUpperCase();
}

String _when(DateTime? time) {
  if (time == null) return '';
  final now = DateTime.now();
  if (time.year == now.year && time.month == now.month && time.day == now.day) {
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    return '$hour:${time.minute.toString().padLeft(2, '0')} ${time.hour < 12 ? 'AM' : 'PM'}';
  }
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${time.day} ${months[time.month - 1]}';
}

/// Private conversations between the school office, teachers and parents.
class MessagesScreen extends ConsumerWidget {
  const MessagesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversationsAsync = ref.watch(conversationsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: const Text('Messages', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AppColors.textPrimary)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.edit_outlined),
        label: const Text('New message'),
        onPressed: () => showContactPicker(context),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(conversationsProvider),
        child: conversationsAsync.when(
          loading: () => const LoadingView(),
          error: (error, _) => ListView(children: [ErrorStateView(message: friendlyError(ref, error))]),
          data: (conversations) {
            if (conversations.isEmpty) {
              return ListView(children: const [
                EmptyState(
                  icon: Icons.forum_outlined,
                  title: 'No messages yet',
                  message: 'Start a conversation with the school office, a teacher or a parent you are connected to.',
                ),
              ]);
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 96),
              itemCount: conversations.length,
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 72, color: AppColors.border),
              itemBuilder: (context, index) => _ConversationTile(conversation: conversations[index]),
            );
          },
        ),
      ),
    );
  }
}

class _ConversationTile extends ConsumerWidget {
  const _ConversationTile({required this.conversation});

  final ConversationSummary conversation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = conversation.unreadCount > 0;
    return InkWell(
      onTap: () async {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(conversationId: conversation.id)));
        ref.invalidate(conversationsProvider);
      },
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            UserAvatar(radius: 22, initials: _initials(conversation.other.fullName)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          conversation.other.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 14.5, fontWeight: unread ? FontWeight.w800 : FontWeight.w600,
                              color: AppColors.textPrimary),
                        ),
                      ),
                      Text(_when(conversation.lastMessageAt),
                          style: TextStyle(fontSize: 11.5, color: unread ? AppColors.primary : AppColors.textMuted)),
                    ],
                  ),
                  Text(conversation.other.context,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${conversation.lastMessageIsMine ? 'You: ' : ''}${conversation.lastMessage}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: unread ? AppColors.textPrimary : AppColors.textSecondary,
                              fontWeight: unread ? FontWeight.w600 : FontWeight.w400),
                        ),
                      ),
                      if (unread)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(100)),
                          child: Text('${conversation.unreadCount}',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Picks someone to write to. The list comes from the server, so it only ever
/// contains people this user is allowed to message.
Future<void> showContactPicker(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (sheetContext) => FractionallySizedBox(
      heightFactor: 0.85,
      child: _ContactPicker(hostContext: context),
    ),
  );
}

class _ContactPicker extends ConsumerStatefulWidget {
  const _ContactPicker({required this.hostContext});

  final BuildContext hostContext;

  @override
  ConsumerState<_ContactPicker> createState() => _ContactPickerState();
}

class _ContactPickerState extends ConsumerState<_ContactPicker> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final contactsAsync = ref.watch(messageContactsProvider(_search));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 18, 20, 4),
          child: Text('New message', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: SearchField(hintText: "Search by name or child's name", onSearch: (term) => setState(() => _search = term)),
        ),
        Expanded(
          child: contactsAsync.when(
            loading: () => const LoadingView(),
            error: (error, _) => ErrorStateView(message: friendlyError(ref, error)),
            data: (contacts) => contacts.isEmpty
                ? const EmptyState(icon: Icons.person_search_outlined, title: 'No one to message',
                    message: 'You can message the school office, and the teachers or parents connected to your classes.')
                : ListView.builder(
                    itemCount: contacts.length,
                    itemBuilder: (context, index) {
                      final contact = contacts[index];
                      return ListTile(
                        leading: UserAvatar(radius: 18, initials: _initials(contact.fullName)),
                        title: Text(contact.fullName, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(contact.context, maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            widget.hostContext,
                            MaterialPageRoute(builder: (_) => ChatScreen.newConversation(recipient: contact)),
                          );
                        },
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}
