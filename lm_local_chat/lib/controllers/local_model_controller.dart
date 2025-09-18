import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
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
  });

  final String id;
  final String name;
  final String sizeLabel;
  final String license;
  final String description;
  final String sourceUrl;
}

class LocalModelState {
  LocalModelState({required this.descriptor});

  final LocalModelDescriptor descriptor;
  LocalModelStatus status = LocalModelStatus.notInstalled;
  double progress = 0;

  Map<String, dynamic> toJson() => {
    'status': status.index,
    'progress': progress,
  };

  void apply(Map<String, dynamic> json) {
    final statusIndex = json['status'] as int?;
    if (statusIndex != null &&
        statusIndex >= 0 &&
        statusIndex < LocalModelStatus.values.length) {
      status = LocalModelStatus.values[statusIndex];
    }
    progress = (json['progress'] as num?)?.toDouble() ?? progress;
  }
}

class LocalModelController extends ChangeNotifier {
  LocalModelController();

  static const _storageKey = 'orbit_local_models';

  final List<LocalModelDescriptor> _availableDescriptors = const [
    LocalModelDescriptor(
      id: 'phi-2-q4',
      name: 'Phi-2 Q4',
      sizeLabel: '1.7 GB',
      license: 'MIT',
      description:
          'Microsoft Phi-2 quantised (Q4) – fast, compact general model ideal for on-device reasoning.',
      sourceUrl: 'https://huggingface.co/TheBloke/phi-2-GGUF',
    ),
    LocalModelDescriptor(
      id: 'tinydolphin-phi-2',
      name: 'TinyDolphin Phi-2',
      sizeLabel: '1.1 GB',
      license: 'Apache-2.0',
      description:
          'A dialogue-tuned variant of Phi-2 optimised for conversational tasks in low-resource environments.',
      sourceUrl: 'https://huggingface.co/cocktailpeanut/tinydolphin-phi-2-GGUF',
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
    ),
  ];

  final List<LocalModelState> _models = [];
  bool _initialised = false;
  Timer? _downloadTimer;

  List<LocalModelState> get models => List.unmodifiable(_models);

  Future<void> initialise() async {
    if (_initialised) return;
    _models
      ..clear()
      ..addAll(
        _availableDescriptors.map(
          (descriptor) => LocalModelState(descriptor: descriptor),
        ),
      );
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
    _initialised = true;
    notifyListeners();
  }

  Future<void> startDownload(String id) async {
    final model = _models.firstWhere((m) => m.descriptor.id == id);
    if (model.status == LocalModelStatus.downloading) {
      return;
    }
    if (model.status == LocalModelStatus.installed) {
      return;
    }
    model.status = LocalModelStatus.downloading;
    model.progress = 0;
    notifyListeners();

    _downloadTimer?.cancel();
    int tick = 0;
    _downloadTimer = Timer.periodic(const Duration(milliseconds: 250), (timer) {
      tick++;
      model.progress = (tick / 20).clamp(0.0, 0.95);
      notifyListeners();
    });

    await Future.delayed(const Duration(seconds: 6));
    _downloadTimer?.cancel();
    _downloadTimer = null;
    model.status = LocalModelStatus.installed;
    model.progress = 1.0;
    await _persist();
    notifyListeners();
  }

  Future<void> removeModel(String id) async {
    final model = _models.firstWhere((m) => m.descriptor.id == id);
    model.status = LocalModelStatus.notInstalled;
    model.progress = 0;
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = {
      for (final model in _models) model.descriptor.id: model.toJson(),
    };
    await prefs.setString(_storageKey, jsonEncode(payload));
  }

  @override
  void dispose() {
    _downloadTimer?.cancel();
    super.dispose();
  }
}
