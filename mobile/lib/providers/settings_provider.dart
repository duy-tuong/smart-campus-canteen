import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/app_config.dart';

/// Cài đặt của ứng dụng (lưu trên máy bằng shared_preferences):
///  - Giao diện Sáng / Tối / Theo hệ thống
///  - Địa chỉ máy chủ backend
class SettingsProvider extends ChangeNotifier {
  SettingsProvider(this._prefs)
    : _themeMode = _readThemeMode(_prefs),
      _apiBaseUrl = _prefs.getString(_kApiBaseUrl) ?? AppConfig.defaultApiBaseUrl;

  static const _kThemeMode = 'settings.themeMode';
  static const _kApiBaseUrl = 'settings.apiBaseUrl';

  final SharedPreferences _prefs;
  ThemeMode _themeMode;
  String _apiBaseUrl;

  static Future<SettingsProvider> load() async => SettingsProvider(await SharedPreferences.getInstance());

  ThemeMode get themeMode => _themeMode;
  String get apiBaseUrl => _apiBaseUrl;
  bool get isUsingDefaultServer => _apiBaseUrl == AppConfig.defaultApiBaseUrl;

  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == _themeMode) return;
    _themeMode = mode;
    notifyListeners();
    await _prefs.setString(_kThemeMode, mode.name);
  }

  /// Chuyển nhanh Sáng ↔ Tối (nút trên thanh tiêu đề). Đang theo hệ thống thì dựa vào độ sáng hiện tại.
  Future<void> toggleTheme(Brightness current) =>
      setThemeMode(current == Brightness.dark ? ThemeMode.light : ThemeMode.dark);

  Future<void> setApiBaseUrl(String url) async {
    final normalized = AppConfig.normalizeBaseUrl(url);
    if (normalized == _apiBaseUrl) return;
    _apiBaseUrl = normalized;
    notifyListeners();
    await _prefs.setString(_kApiBaseUrl, normalized);
  }

  Future<void> resetApiBaseUrl() async {
    _apiBaseUrl = AppConfig.defaultApiBaseUrl;
    notifyListeners();
    await _prefs.remove(_kApiBaseUrl);
  }

  static ThemeMode _readThemeMode(SharedPreferences prefs) => switch (prefs.getString(_kThemeMode)) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
}
