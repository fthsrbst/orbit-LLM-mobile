import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_session.dart';

class ChatStorageService {
  static const _sessionsKey = 'orbit_chat_sessions';
  static const int _maxSessions = 30;

  Future<List<ChatSession>> loadSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sessionsKey);
    if (raw == null) return const [];
    return chatSessionsFromJson(raw);
  }

  Future<void> saveSessions(List<ChatSession> sessions) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = sessions.take(_maxSessions).toList(growable: false);
    await prefs.setString(_sessionsKey, trimmed.toJsonString());
  }

  Future<void> upsertSession(ChatSession session) async {
    final sessions = await loadSessions();
    final existingIndex = sessions.indexWhere((item) => item.id == session.id);
    final updated = [...sessions];
    if (existingIndex >= 0) {
      updated[existingIndex] = session;
    } else {
      updated.insert(0, session);
    }
    await saveSessions(updated);
  }

  Future<void> deleteSession(String sessionId) async {
    final sessions = await loadSessions();
    final updated = sessions
        .where((s) => s.id != sessionId)
        .toList(growable: false);
    await saveSessions(updated);
  }
}
