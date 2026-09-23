import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tema tercihi. React tarafindaki theme.js karsiligi: tercih cihazda saklanir
/// ve giris ekrani dahil tum ekranlarda gecerli olur.
class ThemePreference extends ChangeNotifier {
  static const _key = 'theme';
  ThemeMode _mode = ThemeMode.light;

  ThemeMode get mode => _mode;
  bool get isDark => _mode == ThemeMode.dark;

  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    _mode = prefs.getString(_key) == 'dark' ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }

  Future<void> set(bool dark) async {
    _mode = dark ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, dark ? 'dark' : 'light');
  }
}

final themePreference = ThemePreference();
