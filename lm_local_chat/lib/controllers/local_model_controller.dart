import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum LocalModelStatus { notInstalled, downloading, installed }

class LocalModelDescriptor {
  const LocalModelDescriptor({
    required this.id,
    required this.name,
    required this.sizeLabel,
    required this.license,
    required this.description,
    required this.sourceUrl,
    required this.downloadUrl,
    required this.fileName,
  });

  final String id;
  final String name;
  final String sizeLabel;
  final String license;
  final String description;
  final String sourceUrl;
  final String downloadUrl;
  final String fileName;
}

class LocalModelState {
  LocalModelState({required this.descriptor});

  final LocalModelDescriptor descriptor;
  LocalModelStatus status = LocalModelStatus.notInstalled;
  double progress = 0;
  String? localPath;

  Map<String, dynamic> toJson() => {
    'status': status.index,
    'progress': progress,
    'localPath': localPath,
  };

  void apply(Map<String, dynamic> json) {
    final statusIndex = json['status'] as int?;
    if (statusIndex != null &&
        statusIndex >= 0 &&
        statusIndex < LocalModelStatus.values.length) {
      status = LocalModelStatus.values[statusIndex];
    }
    progress = (json['progress'] as num?)?.toDouble() ?? progress;
    localPath = json['localPath'] as String? ?? localPath;
  }
}

class LocalModelController extends ChangeNotifier {
  LocalModelController();

  static const _storageKey = 'orbit_local_models';
  static const _activeModelKey = 'orbit_local_active_model';

  final List<LocalModelDescriptor> _availableDescriptors = const [
    LocalModelDescriptor(
      id: 'phi-2-q4',
      name: 'Phi-2 Q4',
      sizeLabel: '1.7 GB',
      license: 'MIT',
      description:
          'Microsoft Phi-2 quantised (Q4) – fast, compact general model ideal for on-device reasoning.',
      sourceUrl: 'https://huggingface.co/TheBloke/phi-2-GGUF',
      downloadUrl:
          'https://huggingface.co/TheBloke/phi-2-GGUF/resolve/main/phi-2.Q4_K_M.gguf?download=1',
      fileName: 'phi-2-q4_k_m.gguf',
    ),
    LocalModelDescriptor(
      id: 'phi-3-mini-q4',
      name: 'Phi-3 Mini 4K Q4',
      sizeLabel: '2.2 GB',
      license: 'MIT',
      description:
          'Phi-3 Mini 4K Instruct quantised to Q4 – multilingual capable assistant aligned for chat.',
      sourceUrl: 'https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-gguf',
      downloadUrl:
          'https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-gguf/resolve/main/Phi-3-mini-4k-instruct-q4.gguf?download=1',
      fileName: 'phi-3-mini-4k-q4.gguf',
    ),
    LocalModelDescriptor(
      id: 'mistral-instruct-q4',
      name: 'Mistral Instruct Q4',
      sizeLabel: '3.9 GB',
      license: 'Apache-2.0',
      description:
          'Mistral 7B Instruct quantised to Q4 for mobile inference. Supports multiturn chat and tool usage.',
      sourceUrl:
          'https://huggingface.co/TheBloke/Mistral-7B-Instruct-v0.2-GGUF',
      downloadUrl:
          'https://huggingface.co/TheBloke/Mistral-7B-Instruct-v0.2-GGUF/resolve/main/mistral-7b-instruct-v0.2.Q4_K_M.gguf?download=1',
      fileName: 'mistral-7b-instruct-q4_k_m.gguf',
    ),
  ];

  final List<LocalModelState> _models = [];
  bool _initialised = false;
  String? _activeModelId;
  Directory? _modelsDirectory;
  final http.Client _client = http.Client();
  final Map<String, Future<void>> _activeDownloads = {};

  List<LocalModelState> get models => List.unmodifiable(_models);
  String? get activeModelId => _activeModelId;
  LocalModelState? get activeModelState {
    if (_activeModelId == null) return null;
    for (final model in _models) {
      if (model.descriptor.id == _activeModelId &&
          model.status == LocalModelStatus.installed) {
        return model;
      }
    }
    return null;
  }

  Future<void> initialise() async {
    if (_initialised) return;
    _models
      ..clear()
      ..addAll(
        _availableDescriptors.map(
          (descriptor) => LocalModelState(descriptor: descriptor),
        ),
      );
    await _ensureModelsDirectory();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        for (final model in _models) {
          final stored = decoded[model.descriptor.id];
          if (stored is Map<String, dynamic>) {
            model.apply(stored);
          }
        }
      } catch (_) {
        // ignore corrupt payloads
      }
    }

    var needsPersist = false;
    for (final model in _models) {
      switch (model.status) {
        case LocalModelStatus.installed:
          final path = model.localPath;
          if (path == null) {
            model.status = LocalModelStatus.notInstalled;
            model.progress = 0;
            needsPersist = true;
            break;
          }
          final file = File(path);
          final exists = await file.exists();
          if (!exists) {
            model.status = LocalModelStatus.notInstalled;
            model.progress = 0;
            model.localPath = null;
            needsPersist = true;
          } else {
            model.progress = 1.0;
          }
          break;
        case LocalModelStatus.downloading:
          model.status = LocalModelStatus.notInstalled;
          model.progress = 0;
          model.localPath = null;
          needsPersist = true;
          break;
        case LocalModelStatus.notInstalled:
          model.progress = 0;
          if (model.localPath != null) {
            model.localPath = null;
            needsPersist = true;
          }
          break;
      }
    }
    if (needsPersist) {
      await _persist();
    }

    final activeId = prefs.getString(_activeModelKey);
    if (activeId != null) {
      for (final model in _models) {
        if (model.descriptor.id == activeId &&
            model.status == LocalModelStatus.installed) {
          _activeModelId = activeId;
          break;
        }
      }
      if (_activeModelId != activeId) {
        _activeModelId = null;
      }
    } else {
      _activeModelId = null;
    }
    if (_activeModelId != null && activeModelState == null) {
      _activeModelId = null;
      await _persistActive();
    }
    _initialised = true;
    notifyListeners();
  }

  Future<Directory> _ensureModelsDirectory() async {
    if (_modelsDirectory != null) return _modelsDirectory!;
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/orbit_models');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _modelsDirectory = dir;
    return dir;
  }

  Future<void> startDownload(String id) async {
    await initialise();
    final model = _models.firstWhere((m) => m.descriptor.id == id);
    if (model.status == LocalModelStatus.installed) {
      return;
    }
    final active = _activeDownloads[id];
    if (active != null) {
      await active;
      return;
    }
    final future = _downloadModel(model);
    _activeDownloads[id] = future;
    try {
      await future;
    } finally {
      _activeDownloads.remove(id);
    }
  }

  Future<void> removeModel(String id) async {
    final model = _models.firstWhere((m) => m.descriptor.id == id);
    if (model.status == LocalModelStatus.downloading) {
      return;
    }
    final path = model.localPath;
    if (path != null) {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    }
    model.status = LocalModelStatus.notInstalled;
    model.progress = 0;
    model.localPath = null;
    await _persist();
    if (_activeModelId == id) {
      _activeModelId = null;
      await _persistActive();
    }
    notifyListeners();
  }

  Future<void> setActiveModel(String id) async {
    final model = _models.firstWhere((m) => m.descriptor.id == id);
    if (model.status != LocalModelStatus.installed) {
      return;
    }
    if (_activeModelId == id) {
      return;
    }
    _activeModelId = id;
    await _persistActive();
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = {
      for (final model in _models) model.descriptor.id: model.toJson(),
    };
    await prefs.setString(_storageKey, jsonEncode(payload));
  }

  Future<void> _persistActive() async {
    final prefs = await SharedPreferences.getInstance();
    final id = _activeModelId;
    if (id == null) {
      await prefs.remove(_activeModelKey);
    } else {
      await prefs.setString(_activeModelKey, id);
    }
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  Future<void> _downloadModel(LocalModelState model) async {
    final descriptor = model.descriptor;
    model.status = LocalModelStatus.downloading;
    model.progress = 0;
    model.localPath = null;
    notifyListeners();

    final dir = await _ensureModelsDirectory();
    final file = File('${dir.path}/${descriptor.fileName}');
    if (await file.exists()) {
      await file.delete();
    }

    final request = http.Request('GET', Uri.parse(descriptor.downloadUrl))
      ..headers[HttpHeaders.userAgentHeader] = 'OrbitApp/1.0'
      ..headers[HttpHeaders.acceptHeader] = 'application/octet-stream';
    http.StreamedResponse response;
    try {
      response = await _client.send(request);
    } catch (error) {
      model.status = LocalModelStatus.notInstalled;
      notifyListeners();
      rethrow;
    }

    if (response.statusCode != 200) {
      model.status = LocalModelStatus.notInstalled;
      notifyListeners();
      throw HttpException(
        'Model indirme talebi ${response.statusCode} ile sonuçlandı.',
        uri: Uri.parse(descriptor.downloadUrl),
      );
    }

    final totalBytes = response.contentLength ?? 0;
    var receivedBytes = 0;
    IOSink? sink;

    try {
      sink = file.openWrite();
      await for (final chunk in response.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0) {
          model.progress = (receivedBytes / totalBytes).clamp(0.0, 0.995);
        } else {
          model.progress = (model.progress + 0.01).clamp(0.0, 0.95);
        }
        notifyListeners();
      }
      await sink.flush();
      await sink.close();
      sink = null;

      model.status = LocalModelStatus.installed;
      model.progress = 1.0;
      model.localPath = file.path;
      await _persist();
      if (_activeModelId == null) {
        _activeModelId = descriptor.id;
        await _persistActive();
      }
      notifyListeners();
    } catch (error) {
      await sink?.close();
      if (await file.exists()) {
        await file.delete();
      }
      model.status = LocalModelStatus.notInstalled;
      model.progress = 0;
      model.localPath = null;
      notifyListeners();
      rethrow;
    }
  }
}
