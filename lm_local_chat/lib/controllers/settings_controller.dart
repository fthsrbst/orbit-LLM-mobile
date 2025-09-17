import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsController extends ChangeNotifier {
  SettingsController();

  static const _themeKey = 'settings_theme_mode';
  static const _accentKey = 'settings_accent_color';
  static const _fontKey = 'settings_body_font';
  static const _scaleKey = 'settings_text_scale';
  static const _shaderKey = 'settings_shader_enabled';

  ThemeMode _themeMode = ThemeMode.system;
  Color _accentColor = const Color(0xFF6C6CFF);
  String _bodyFont = 'Outfit';
  double _textScale = 1.0;
  bool _useShader = true;

  ThemeMode get themeMode => _themeMode;
  Color get accentColor => _accentColor;
  String get bodyFont => _bodyFont;
  double get textScale => _textScale;
  bool get useShader => _useShader;

  Future<void> initialise() async {
    final prefs = await SharedPreferences.getInstance();
    final themeIndex = prefs.getInt(_themeKey);
    if (themeIndex != null &&
        themeIndex >= 0 &&
        themeIndex < ThemeMode.values.length) {
      _themeMode = ThemeMode.values[themeIndex];
    }
    final accentHex = prefs.getString(_accentKey);
    if (accentHex != null) {
      _accentColor = _fromHex(accentHex);
    }
    _bodyFont = prefs.getString(_fontKey) ?? _bodyFont;
    _textScale = prefs.getDouble(_scaleKey) ?? _textScale;
    _useShader = prefs.getBool(_shaderKey) ?? _useShader;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeKey, mode.index);
  }

  Future<void> setAccentColor(Color color) async {
    if (_accentColor.toARGB32() == color.toARGB32()) return;
    _accentColor = color;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accentKey, _toHex(color));
  }

  Future<void> setBodyFont(String font) async {
    if (_bodyFont == font) return;
    _bodyFont = font;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_fontKey, font);
  }

  Future<void> setTextScale(double scale) async {
    _textScale = scale.clamp(0.85, 1.4);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_scaleKey, _textScale);
  }

  Future<void> setShaderEnabled(bool value) async {
    if (_useShader == value) return;
    _useShader = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_shaderKey, value);
  }

  String _toHex(Color color) =>
      color.toARGB32().toRadixString(16).padLeft(8, '0');

  Color _fromHex(String hex) {
    final value = int.tryParse(hex, radix: 16);
    if (value == null) return _accentColor;
    return Color(value);
  }
}
