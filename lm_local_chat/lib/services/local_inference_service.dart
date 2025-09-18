import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:llama_cpp_dart/llama_cpp_dart.dart';

import '../models/chat_message.dart';

class LocalInferenceService {
  LocalInferenceService() {
    if (Platform.isWindows) {
      Llama.libraryPath = 'llama.dll';
    } else if (Platform.isMacOS || Platform.isIOS) {
      Llama.libraryPath = 'libllama.dylib';
    } else {
      Llama.libraryPath = 'libllama.so';
    }
  }

  LlamaParent? _parent;
  String? _modelPath;
  String? _modelId;
  double _temperature = 0.7;
  Future<void>? _loadingFuture;
  bool _isDisposed = false;

  Future<void> ensureModelLoaded({
    required String modelId,
    required String modelPath,
    double temperature = 0.7,
  }) async {
    if (_isDisposed) {
      throw StateError('Yerel çıkarım servisi kapatıldı.');
    }

    if (_parent != null &&
        _modelPath == modelPath &&
        _modelId == modelId &&
        (_parent!.status == LlamaStatus.ready ||
            _parent!.status == LlamaStatus.generating) &&
        (temperature - _temperature).abs() < 0.01) {
      return;
    }

    if (_loadingFuture != null) {
      await _loadingFuture;
      if (_parent != null &&
          _modelPath == modelPath &&
          _modelId == modelId &&
          (_parent!.status == LlamaStatus.ready ||
              _parent!.status == LlamaStatus.generating) &&
          (temperature - _temperature).abs() < 0.01) {
        return;
      }
    }

    _loadingFuture = _initialiseParent(
      modelId: modelId,
      modelPath: modelPath,
      temperature: temperature,
    );
    try {
      await _loadingFuture;
    } finally {
      _loadingFuture = null;
    }
  }

  Stream<String> generateResponse({required List<ChatMessage> history}) {
    final parent = _parent;
    if (parent == null || parent.status == LlamaStatus.disposed) {
      throw StateError('Yerel model yüklenmedi.');
    }
    final controller = StreamController<String>();

    StreamSubscription<String>? tokenSub;
    StreamSubscription<CompletionEvent>? completionSub;

    () async {
      try {
        final chatHistory = ChatHistory()
          ..addMessage(
            role: Role.system,
            content:
                'You are Orbit, a concise assistant running fully offline on the user\'s device.',
          );
        for (final message in history) {
          final content = message.content.trim();
          if (content.isEmpty) continue;
          final role = message.role == ChatRole.user
              ? Role.user
              : Role.assistant;
          chatHistory.addMessage(role: role, content: content);
        }
        final prompt = chatHistory.exportFormat(ChatFormat.chatml);

        final done = Completer<void>();
        String? activePromptId;

        completionSub = parent.completions.listen((event) {
          if (activePromptId == null || event.promptId != activePromptId) {
            return;
          }
          if (event.success) {
            if (!done.isCompleted) {
              done.complete();
            }
          } else {
            if (!done.isCompleted) {
              done.completeError(
                StateError(
                  event.errorDetails ?? 'Yerel model yanıtı tamamlanamadı.',
                ),
              );
            }
          }
        });

        tokenSub = parent.stream.listen(
          controller.add,
          onError: (error, stackTrace) {
            if (!done.isCompleted) {
              done.completeError(error, stackTrace);
            }
          },
        );

        activePromptId = await parent.sendPrompt(prompt);
        await done.future;
        if (!controller.isClosed) {
          await controller.close();
        }
      } catch (error, stackTrace) {
        if (!controller.isClosed) {
          controller.addError(error, stackTrace);
          await controller.close();
        }
      } finally {
        await tokenSub?.cancel();
        await completionSub?.cancel();
      }
    }();

    return controller.stream;
  }

  Future<void> dispose() async {
    _isDisposed = true;
    final loading = _loadingFuture;
    if (loading != null) {
      try {
        await loading;
      } catch (_) {
        // ignore errors during teardown
      }
    }
    final parent = _parent;
    _parent = null;
    if (parent != null) {
      await parent.dispose();
    }
  }

  Future<void> _initialiseParent({
    required String modelId,
    required String modelPath,
    required double temperature,
  }) async {
    final file = File(modelPath);
    if (!await file.exists()) {
      throw StateError('Model dosyası bulunamadı: $modelPath');
    }

    await _parent?.dispose();

    final cpuCount = max(2, Platform.numberOfProcessors);
    final contextParams = ContextParams()
      ..nCtx = 4096
      ..nBatch = 256
      ..nUbatch = 256
      ..nThreads = cpuCount
      ..nThreadsBatch = max(2, cpuCount ~/ 2)
      ..noPerfTimings = true
      ..offloadKqv = !(Platform.isAndroid || Platform.isIOS);

    final samplerParams = SamplerParams()
      ..temp = temperature
      ..topK = 40
      ..topP = 0.95
      ..penaltyRepeat = 1.1
      ..penaltyLastTokens = 64;

    final loadCommand = LlamaLoad(
      path: modelPath,
      modelParams: ModelParams(),
      contextParams: contextParams,
      samplingParams: samplerParams,
      format: ChatMLFormat(),
    );

    final parent = LlamaParent(loadCommand, ChatMLFormat());
    await parent.init();
    _parent = parent;
    _modelId = modelId;
    _modelPath = modelPath;
    _temperature = temperature;
  }
}
