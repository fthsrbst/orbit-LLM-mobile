enum ChatRole { user, assistant }

class ChatMessage {
  ChatMessage({
    required this.role,
    required this.content,
    this.tokensPerSecond,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  final ChatRole role;
  final String content;
  final double? tokensPerSecond;
  final DateTime timestamp;

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final roleString = json['role']?.toString() ?? 'user';
    final role = ChatRole.values.firstWhere(
      (value) => value.name == roleString,
      orElse: () => ChatRole.user,
    );
    return ChatMessage(
      role: role,
      content: json['content']?.toString() ?? '',
      tokensPerSecond: (json['tokensPerSecond'] as num?)?.toDouble(),
      timestamp:
          DateTime.tryParse(json['timestamp']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  ChatMessage copyWith({
    ChatRole? role,
    String? content,
    double? tokensPerSecond,
    DateTime? timestamp,
  }) {
    return ChatMessage(
      role: role ?? this.role,
      content: content ?? this.content,
      tokensPerSecond: tokensPerSecond ?? this.tokensPerSecond,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  Map<String, dynamic> toJson() => {
    'role': role.name,
    'content': content,
    'tokensPerSecond': tokensPerSecond,
    'timestamp': timestamp.toIso8601String(),
  };
}
