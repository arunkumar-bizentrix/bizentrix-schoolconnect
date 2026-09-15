import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/page_result.dart';

int _int(dynamic v) => v is int ? v : int.tryParse('${v ?? ''}') ?? 0;

/// Someone the signed-in user can talk to, with who they are to them
/// ("Parent of Kavya (Grade 5 - A)", "Class teacher, Grade 5 - A").
class MessageContact {
  const MessageContact({required this.id, required this.fullName, required this.role, this.context = ''});

  final int id;
  final String fullName;
  final String role;
  final String context;

  factory MessageContact.fromJson(Map<String, dynamic> json) => MessageContact(
        id: _int(json['id']),
        fullName: '${json['full_name'] ?? ''}',
        role: '${json['role'] ?? ''}',
        context: '${json['context'] ?? ''}',
      );
}

class ConversationSummary {
  const ConversationSummary({
    required this.id,
    required this.other,
    required this.lastMessage,
    required this.lastMessageIsMine,
    required this.lastMessageAt,
    required this.unreadCount,
    required this.canReply,
  });

  final int id;
  final MessageContact other;
  final String lastMessage;
  final bool lastMessageIsMine;
  final DateTime? lastMessageAt;
  final int unreadCount;
  final bool canReply;

  factory ConversationSummary.fromJson(Map<String, dynamic> json) => ConversationSummary(
        id: _int(json['id']),
        other: MessageContact.fromJson(Map<String, dynamic>.from(json['other'] as Map)),
        lastMessage: '${json['last_message'] ?? ''}',
        lastMessageIsMine: json['last_message_is_mine'] == true,
        lastMessageAt: DateTime.tryParse('${json['last_message_at'] ?? ''}')?.toLocal(),
        unreadCount: _int(json['unread_count']),
        canReply: json['can_reply'] != false,
      );
}

class ChatMessage {
  const ChatMessage({required this.id, required this.body, required this.isMine, this.createdAt, this.readAt});

  final int id;
  final String body;
  final bool isMine;
  final DateTime? createdAt;
  final DateTime? readAt;

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: _int(json['id']),
        body: '${json['body'] ?? ''}',
        isMine: json['is_mine'] == true,
        createdAt: DateTime.tryParse('${json['created_at'] ?? ''}')?.toLocal(),
        readAt: DateTime.tryParse('${json['read_at'] ?? ''}')?.toLocal(),
      );
}

class ChatThread {
  const ChatThread({required this.id, required this.other, required this.canReply, required this.hasOlder, required this.messages});

  final int id;
  final MessageContact other;
  final bool canReply;
  final bool hasOlder;
  final List<ChatMessage> messages;

  factory ChatThread.fromJson(Map<String, dynamic> json) => ChatThread(
        id: _int(json['id']),
        other: MessageContact.fromJson(Map<String, dynamic>.from(json['other'] as Map)),
        canReply: json['can_reply'] != false,
        hasOlder: json['has_older'] == true,
        messages: (json['messages'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ChatMessage.fromJson)
            .toList(),
      );
}

final conversationsProvider = FutureProvider.autoDispose<List<ConversationSummary>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final response = await api.dio.get(ApiEndpoints.conversations);
  return PageResult.parse(response.data, ConversationSummary.fromJson).items;
});

final chatThreadProvider = FutureProvider.autoDispose.family<ChatThread, int>((ref, id) async {
  final api = ref.watch(apiClientProvider);
  final thread = ChatThread.fromJson(Map<String, dynamic>.from((await api.dio.get(ApiEndpoints.conversation(id))).data as Map));
  // Opening a thread marks it read on the server.
  ref.invalidate(unreadMessagesProvider);
  return thread;
});

final messageContactsProvider = FutureProvider.autoDispose.family<List<MessageContact>, String>((ref, search) async {
  final api = ref.watch(apiClientProvider);
  final response = await api.dio.get(
    ApiEndpoints.messageContacts,
    queryParameters: {if (search.trim().isNotEmpty) 'search': search.trim()},
  );
  return (response.data as List).whereType<Map<String, dynamic>>().map(MessageContact.fromJson).toList();
});

final unreadMessagesProvider = FutureProvider<int>((ref) async {
  final api = ref.watch(apiClientProvider);
  try {
    final response = await api.dio.get(ApiEndpoints.messagesUnreadCount);
    return _int((response.data as Map)['unread_count']);
  } catch (_) {
    return 0;
  }
});

class MessageActions {
  MessageActions(this.ref);

  final Ref ref;

  ApiClient get _api => ref.read(apiClientProvider);

  /// Starts (or continues) a conversation. Returns (conversationId, error).
  Future<(int?, String?)> start(int recipientId, String body) async {
    try {
      final response = await _api.dio.post(ApiEndpoints.conversations, data: {'recipient_id': recipientId, 'body': body});
      ref.invalidate(conversationsProvider);
      return (_int((response.data as Map)['id']), null);
    } catch (e) {
      return (null, _api.handleError(e).message);
    }
  }

  Future<String?> send(int conversationId, String body) async {
    try {
      await _api.dio.post(ApiEndpoints.conversationMessages(conversationId), data: {'body': body});
      ref.invalidate(chatThreadProvider(conversationId));
      ref.invalidate(conversationsProvider);
      return null;
    } catch (e) {
      return _api.handleError(e).message;
    }
  }
}

final messageActionsProvider = Provider<MessageActions>((ref) => MessageActions(ref));
