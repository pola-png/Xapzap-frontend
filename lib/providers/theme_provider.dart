import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider with ChangeNotifier {
  ThemeMode _themeMode;

  ThemeProvider([ThemeMode initialMode = ThemeMode.system]) : _themeMode = initialMode {
    _loadSavedTheme();
  }

  ThemeMode get themeMode => _themeMode;

  void setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('themeMode', mode.name);
  }

  Future<void> _loadSavedTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('themeMode');
    if (saved == null) return;
    try {
      final mode = ThemeMode.values.firstWhere(
        (m) => m.name == saved,
        orElse: () => ThemeMode.system,
      );
      if (mode != _themeMode) {
        _themeMode = mode;
        notifyListeners();
      }
    } catch (_) {
      // Ignore invalid saved values and keep current mode.
    }
  }
}
