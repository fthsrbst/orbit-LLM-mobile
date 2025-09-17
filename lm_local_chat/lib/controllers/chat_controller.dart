import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../models/chat_message.dart';
import '../models/chat_session.dart';
import '../services/chat_storage_service.dart';
import '../services/lm_studio_service.dart';
import 'session_controller.dart';

enum ChatFlowState { idle, thinking, generating }

class ChatController extends ChangeNotifier {
  ChatController(this._service, this._sessionController, this._storage);

  final LmStudioService _service;
  final SessionController _sessionController;
  final ChatStorageService _storage;

  final List<ChatMessage> _messages = <ChatMessage>[];
  bool _isSending = false;
  String? _error;
  ChatFlowState _flowState = ChatFlowState.idle;
  final List<ChatSession> _history = <ChatSession>[];
  String? _sessionId;
  DateTime? _createdAt;

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get isSending => _isSending;
  String? get errorMessage => _error;
  ChatFlowState get flowState => _flowState;
  List<ChatSession> get history => List.unmodifiable(_history);
  bool get hasPersistedChats => _history.isNotEmpty;

  void dismissError() {
    _error = null;
    notifyListeners();
  }

  Future<void> initialise() async {
    final sessions = await _storage.loadSessions();
    _history
      ..clear()
      ..addAll(sessions);
    if (sessions.isNotEmpty) {
      final latest = sessions.first;
      _sessionId = latest.id;
      _createdAt = latest.createdAt;
      _messages
        ..clear()
        ..addAll(latest.messages);
    } else {
      _beginNewSession();
    }
    notifyListeners();
  }

  Future<void> startNewChat() async {
    await _persistSession();
    _messages.clear();
    _flowState = ChatFlowState.idle;
    _beginNewSession();
    notifyListeners();
  }

  Future<void> sendMessage(String content) async {
    if (!_sessionController.isReady) {
      _error = 'Önce bağlantı ve model seçimi yapılmalı.';
      notifyListeners();
      return;
    }
    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final userMessage = ChatMessage(role: ChatRole.user, content: trimmed);
    _messages.add(userMessage);
    _isSending = true;
    _error = null;
    _flowState = ChatFlowState.thinking;
    notifyListeners();

    try {
      final host = _sessionController.host!;
      final port = _sessionController.port;
      final model = _sessionController.selectedModel!;
      final history = _messages
          .map(
            (message) => {
              'role': message.role.name,
              'content': message.content,
            },
          )
          .toList(growable: false);

      final assistantPlaceholder = ChatMessage(
        role: ChatRole.assistant,
        content: '',
      );
      _messages.add(assistantPlaceholder);
      final assistantIndex = _messages.length - 1;
      _flowState = ChatFlowState.generating;
      notifyListeners();

      var fallbackToNonStream = false;
      final buffer = StringBuffer();
      double? tokensPerSecond;

      try {
        await for (final chunk in _service.streamChatCompletion(
          host: host,
          port: port,
          model: model,
          messages: history,
          temperature: _sessionController.temperature,
        )) {
          if (chunk.contentDelta != null) {
            buffer.write(chunk.contentDelta);
            _messages[assistantIndex] = _messages[assistantIndex].copyWith(
              content: buffer.toString(),
            );
            notifyListeners();
          }
          if (chunk.tokensPerSecond != null) {
            tokensPerSecond = chunk.tokensPerSecond;
          }
          if (chunk.done && chunk.contentDelta == null) {
            break;
          }
        }
      } catch (_) {
        fallbackToNonStream = true;
      }

      if (fallbackToNonStream) {
        if (assistantIndex < _messages.length) {
          _messages.removeAt(assistantIndex);
        }
        final result = await _service.sendChatCompletion(
          host: host,
          port: port,
          model: model,
          messages: history,
          temperature: _sessionController.temperature,
        );
        _messages.add(
          ChatMessage(
            role: ChatRole.assistant,
            content: result.content,
            tokensPerSecond: result.tokensPerSecond,
          ),
        );
        notifyListeners();
      } else {
        final finalContent = buffer.toString();
        _messages[assistantIndex] = _messages[assistantIndex].copyWith(
          content: finalContent,
          tokensPerSecond: tokensPerSecond,
        );
        notifyListeners();
      }

      await _persistSession();
    } catch (err) {
      _error = 'Mesaj gönderilemedi: $err';
      while (_messages.isNotEmpty && _messages.last.role != ChatRole.user) {
        _messages.removeLast();
      }
      if (_messages.isNotEmpty && _messages.last.role == ChatRole.user) {
        _messages.removeLast();
      }
    } finally {
      _isSending = false;
      _flowState = ChatFlowState.idle;
      notifyListeners();
    }
  }

  Future<void> loadSession(String sessionId) async {
    final sessions = await _storage.loadSessions();
    final target = sessions.firstWhere(
      (session) => session.id == sessionId,
      orElse: () => sessions.isEmpty
          ? ChatSession(
              id: _sessionId ?? const Uuid().v4(),
              createdAt: DateTime.now(),
              messages: const [],
            )
          : sessions.first,
    );
    _sessionId = target.id;
    _createdAt = target.createdAt;
    _messages
      ..clear()
      ..addAll(target.messages);
    _history
      ..clear()
      ..addAll(sessions);
    _flowState = ChatFlowState.idle;
    notifyListeners();
  }

  Future<void> deleteSession(String sessionId) async {
    await _storage.deleteSession(sessionId);
    final sessions = await _storage.loadSessions();
    _history
      ..clear()
      ..addAll(sessions);
    notifyListeners();
  }

  Future<void> shareSession(ChatSession session) async {
    final text = session.toShareText();
    await Share.share(text, subject: session.title);
  }

  Future<void> shareCurrentSession() async {
    if (_messages.isEmpty) return;
    final session = _currentSessionSnapshot();
    await shareSession(session);
  }

  void _beginNewSession() {
    _sessionId = const Uuid().v4();
    _createdAt = DateTime.now();
  }

  Future<void> _persistSession() async {
    if (_sessionId == null || _messages.isEmpty) {
      return;
    }
    final session = _currentSessionSnapshot();
    await _storage.upsertSession(session);
    final sessions = await _storage.loadSessions();
    _history
      ..clear()
      ..addAll(sessions);
  }

  ChatSession _currentSessionSnapshot() {
    return ChatSession(
      id: _sessionId ?? const Uuid().v4(),
      createdAt: _createdAt ?? DateTime.now(),
      messages: List<ChatMessage>.from(_messages),
    );
  }
}
