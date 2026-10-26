import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService extends ChangeNotifier {
  SettingsService._();
  static final SettingsService instance = SettingsService._();

  static const _themeKey = 'theme_mode';
  static const _discreetKey = 'discreet_notifications';

  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;

  bool _discreet = false;
  bool get discreetNotifications => _discreet;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_themeKey);
      _themeMode = ThemeMode.values.firstWhere(
        (m) => m.name == saved,
        orElse: () => ThemeMode.system,
      );
      _discreet = prefs.getBool(_discreetKey) ?? false;
    } catch (_) {
      // Keep the defaults if reading fails.
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_themeKey, mode.name);
    } catch (_) {
      // The theme still changes for this session even if saving fails.
    }
  }

  Future<void> setDiscreetNotifications(bool value) async {
    _discreet = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_discreetKey, value);
    } catch (_) {
      // Still applies for this session even if saving fails.
    }
  }
}