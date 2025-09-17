import 'dart:convert';

import 'chat_message.dart';

class ChatSession {
  ChatSession({
    required this.id,
    required this.createdAt,
    required List<ChatMessage> messages,
  }) : _messages = List<ChatMessage>.unmodifiable(messages);

  factory ChatSession.fromJson(Map<String, dynamic> json) {
    final messagesJson = json['messages'] as List<dynamic>? ?? const [];
    return ChatSession(
      id: json['id'] as String,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      messages: messagesJson
          .whereType<Map<String, dynamic>>()
          .map(ChatMessage.fromJson)
          .toList(growable: false),
    );
  }

  final String id;
  final DateTime createdAt;
  final List<ChatMessage> _messages;

  List<ChatMessage> get messages => _messages;

  String get title {
    final firstUser = _messages.firstWhere(
      (msg) => msg.role == ChatRole.user,
      orElse: () => _messages.isEmpty
          ? ChatMessage(role: ChatRole.user, content: 'Yeni sohbet')
          : _messages.first,
    );
    return firstUser.content.length > 36
        ? '${firstUser.content.substring(0, 33)}...'
        : firstUser.content;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'messages': _messages.map((m) => m.toJson()).toList(growable: false),
  };

  String toShareText() {
    final buffer = StringBuffer();
    buffer.writeln('Orbit sohbeti — ${createdAt.toLocal()}');
    for (final message in _messages) {
      final label = message.role == ChatRole.user ? 'Sen' : 'Orbit';
      buffer.writeln('\n$label:');
      buffer.writeln(message.content.trim());
      if (message.tokensPerSecond != null) {
        buffer.writeln(
          '(${message.tokensPerSecond!.toStringAsFixed(2)} token/sn)',
        );
      }
    }
    return buffer.toString();
  }
}

extension ChatSessionListEncoding on List<ChatSession> {
  String toJsonString() {
    final list = map((session) => session.toJson()).toList(growable: false);
    return jsonEncode(list);
  }
}

List<ChatSession> chatSessionsFromJson(String source) {
  final decoded = jsonDecode(source);
  if (decoded is! List) return const [];
  return decoded
      .whereType<Map<String, dynamic>>()
      .map(ChatSession.fromJson)
      .toList(growable: false);
}
