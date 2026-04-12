import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class ChatMessage {
  final String role; // 'user' or 'ai'
  final String content;
  final DateTime timestamp;

  ChatMessage({
    required this.role,
    required this.content,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        role: json['role'] as String,
        content: json['content'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
      );
}

class ChatRepository {
  static const String _key = 'vesta_chat_history';

  Future<List<ChatMessage>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_key);
    if (jsonStr == null) return [];
    
    try {
      final List<dynamic> jsonList = jsonDecode(jsonStr);
      return jsonList.map((e) => ChatMessage.fromJson(e)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> saveMessage(ChatMessage message) async {
    final prefs = await SharedPreferences.getInstance();
    final history = await loadHistory();
    history.add(message);
    
    // Store only the last 200 messages to prevent RAM explosion
    if (history.length > 200) {
      history.removeRange(0, history.length - 200);
    }
    
    await prefs.setString(_key, jsonEncode(history.map((e) => e.toJson()).toList()));
  }

  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
