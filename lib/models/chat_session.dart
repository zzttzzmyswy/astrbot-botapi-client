// lib/models/chat_session.dart
//
// 一个会话 = 单一对话上下文（服务端 /sessions 的 id+name）。
// 本地预置 id="default" 的默认会话；服务器为 null 时不发 session_id（兼容老服务器）。
class ChatSession {
  final String id;
  final String name;

  const ChatSession({
    required this.id,
    required this.name,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
      };

  factory ChatSession.fromJson(Map<String, dynamic> json) => ChatSession(
        id: json['id'] as String,
        name: json['name'] as String,
      );

  ChatSession copyWith({
    String? id,
    String? name,
  }) =>
      ChatSession(
        id: id ?? this.id,
        name: name ?? this.name,
      );
}
