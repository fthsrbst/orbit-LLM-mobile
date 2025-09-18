import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';

import '../models/chat_message.dart';

class LocalInferenceService {
  LocalInferenceService();

  LlamaParent? _parent;
  String? _modelPath;
  String? _modelId;
  double _temperature = 0.7;
  Future<void>? _loadingFuture;
  bool _isDisposed = false;
  bool _libraryPathReady = false;
  Future<void>? _libraryFuture;

  void _debug(String message) {
    if (kDebugMode) {
      debugPrint('[LocalInference] $message');
    }
  }

  Future<void> ensureModelLoaded({
    required String modelId,
    required String modelPath,
    double temperature = 0.7,
  }) async {
    if (_isDisposed) {
      throw StateError('Yerel çıkarım servisi kapatıldı.');
    }

    await _ensureLibraryPath();

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
    _debug('Yerel yanıt isteği alındı (geçmiş: ${history.length}).');
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
        _debug('Yerel yanıt tamamlandı.');
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

  Future<void> _ensureLibraryPath() async {
    if (_libraryPathReady) {
      return;
    }
    final pending = _libraryFuture;
    if (pending != null) {
      await pending;
      return;
    }
    final completer = Completer<void>();
    _libraryFuture = completer.future;
    try {
      final override = _readEnv('ORBIT_LLAMA_LIBRARY');
      if (override != null && override.isNotEmpty) {
        final file = File(override);
        if (!await file.exists()) {
          throw StateError(
            'ORBIT_LLAMA_LIBRARY ile belirtilen libllama dosyası bulunamadı: $override',
          );
        }
        Llama.libraryPath = override;
        _debug('libllama yolu ortam değişkeninden yüklendi: $override');
      } else {
        final resolved = await Isolate.resolvePackageUri(
          Uri.parse('package:llama_cpp_dart/llama_cpp_dart.dart'),
        );
        final bundled = await _findBundledLibrary(resolved);
        if (bundled == null) {
          final fallback = _defaultLibraryName();
          throw StateError(
            'libllama kütüphanesi bulunamadı. $fallback dosyasının sistem PATH üzerinde olduğundan '
            'veya ORBIT_LLAMA_LIBRARY ortam değişkeni ile tam yolun belirtildiğinden emin olun.',
          );
        }
        Llama.libraryPath = bundled;
        _debug('libllama bundle içerisinden ayarlandı: $bundled');
      }
      _libraryPathReady = true;
      completer.complete();
    } catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
      rethrow;
    } finally {
      _libraryFuture = null;
    }
  }

  String? _readEnv(String key) {
    try {
      return Platform.environment[key];
    } catch (_) {
      return null;
    }
  }

  String _defaultLibraryName() {
    if (Platform.isWindows) {
      return 'llama.dll';
    }
    if (Platform.isMacOS || Platform.isIOS) {
      return 'libllama.dylib';
    }
    return 'libllama.so';
  }

  Future<String?> _findBundledLibrary(Uri? packageLibrary) async {
    if (packageLibrary == null || packageLibrary.scheme != 'file') {
      return null;
    }
    final packageFile = File.fromUri(packageLibrary);
    final packageDir = packageFile.parent.parent;
    final binDir = Directory('${packageDir.path}/bin');
    if (!await binDir.exists()) {
      return null;
    }

    final candidates = _candidatePathsForAbi(binDir.path);
    for (final candidate in candidates) {
      final file = File(candidate);
      if (await file.exists()) {
        return file.path;
      }
    }

    await for (final entity in binDir.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last.toLowerCase();
      if (name.startsWith('libllama') || name == 'llama.dll') {
        return entity.path;
      }
    }
    return null;
  }

  List<String> _candidatePathsForAbi(String binPath) {
    switch (Abi.current()) {
      case Abi.macosArm64:
        return [
          '$binPath/MAC_ARM64/libllama.dylib',
          '$binPath/SIMULATORARM64/libllama.dylib',
          '$binPath/SIMULATOR64/libllama.dylib',
        ];
      case Abi.iosArm64:
        return [
          '$binPath/OS64/libllama.dylib',
          '$binPath/SIMULATORARM64/libllama.dylib',
        ];
      case Abi.androidArm64:
      case Abi.androidArm:
        return const [];
      default:
        return const [];
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

    _debug('Yerel model yükleniyor: $modelId (${file.path})');

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
    try {
      await parent.init();
    } catch (error, stackTrace) {
      _debug('Model başlatılamadı: $error');
      Error.throwWithStackTrace(
        StateError(
          'Yerel model başlatılamadı: $error. '
          'libllama kütüphanesinin doğru yüklendiğinden emin olun.',
        ),
        stackTrace,
      );
    }
    _debug('Model $modelId hazır.');
    _parent = parent;
    _modelId = modelId;
    _modelPath = modelPath;
    _temperature = temperature;
  }
}
