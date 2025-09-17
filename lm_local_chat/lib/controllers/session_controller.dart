import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/lm_instance.dart';
import '../services/lm_studio_service.dart';

class SessionController extends ChangeNotifier {
  SessionController(this._service);

  final LmStudioService _service;

  String? _host;
  int _port = 1234;
  List<LmStudioInstance> _instances = const [];
  List<String> _models = const [];
  String? _selectedModel;
  double _temperature = 0.7;
  bool _isDiscovering = false;
  bool _isLoadingModels = false;
  String? _error;

  String? get host => _host;
  int get port => _port;
  List<LmStudioInstance> get instances => _instances;
  List<String> get models => _models;
  String? get selectedModel => _selectedModel;
  double get temperature => _temperature;
  bool get isDiscovering => _isDiscovering;
  bool get isLoadingModels => _isLoadingModels;
  String? get errorMessage => _error;
  bool get isReady => _host != null && _selectedModel != null;

  Future<void> initialise() async {
    final prefs = await SharedPreferences.getInstance();
    _host = prefs.getString(_hostKey);
    _port = prefs.getInt(_portKey) ?? 1234;
    _selectedModel = prefs.getString(_modelKey);
    _temperature = prefs.getDouble(_tempKey) ?? 0.7;
    if (_host != null) {
      await refreshModels();
    }
  }

  Future<void> setConnection({required String host, required int port}) async {
    _host = host;
    _port = port;
    _error = null;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_hostKey, host);
    await prefs.setInt(_portKey, port);
    await refreshModels();
  }

  Future<void> refreshModels() async {
    final currentHost = _host;
    if (currentHost == null) return;
    _isLoadingModels = true;
    _error = null;
    notifyListeners();
    try {
      final models = await _service.fetchModels(host: currentHost, port: _port);
      _models = models;
      if (models.isNotEmpty) {
        if (_selectedModel == null || !models.contains(_selectedModel)) {
          _selectedModel = models.first;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_modelKey, _selectedModel!);
        }
      } else {
        _selectedModel = null;
      }
    } catch (err) {
      _error = err.toString();
      _models = const [];
      _selectedModel = null;
    } finally {
      _isLoadingModels = false;
      notifyListeners();
    }
  }

  Future<void> discoverInstances({int port = 1234}) async {
    _isDiscovering = true;
    _error = null;
    notifyListeners();
    try {
      final results = await _service.discoverInstances(port: port);
      _instances = results;
      if (results.isEmpty) {
        _error = 'Ağda LM Studio bulunamadı. Manuel IP giriniz.';
      }
    } catch (err) {
      _error = 'Taramada hata: $err';
    } finally {
      _isDiscovering = false;
      notifyListeners();
    }
  }

  Future<void> selectModel(String modelId) async {
    _selectedModel = modelId;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modelKey, modelId);
  }

  Future<void> updateTemperature(double value) async {
    _temperature = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_tempKey, value);
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  static const _hostKey = 'lm_host';
  static const _portKey = 'lm_port';
  static const _modelKey = 'lm_model';
  static const _tempKey = 'lm_temp';
}
