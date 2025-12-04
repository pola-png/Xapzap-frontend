import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Simple persistent cache for avatar URLs keyed by userId/username.
/// Stored in SharedPreferences so values survive app restarts and
/// are cleared only when the user explicitly logs out.
class AvatarCache {
  static const String _userIdKey = 'avatar_by_user_id';
  static const String _usernameKey = 'avatar_by_username';

  static final Map<String, String?> _byUserId = <String, String?>{};
  static final Map<String, String?> _byUsername = <String, String?>{};

  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final userJson = prefs.getString(_userIdKey);
      final usernameJson = prefs.getString(_usernameKey);

      if (userJson != null && userJson.isNotEmpty) {
        final Map<String, dynamic> decoded = jsonDecode(userJson) as Map<String, dynamic>;
        decoded.forEach((key, value) {
          _byUserId[key] = value as String?;
        });
      }

      if (usernameJson != null && usernameJson.isNotEmpty) {
        final Map<String, dynamic> decoded =
            jsonDecode(usernameJson) as Map<String, dynamic>;
        decoded.forEach((key, value) {
          _byUsername[key] = value as String?;
        });
      }
    } catch (_) {
      // Ignore cache load failures; app will still work.
    }
  }

  static String? getForUserId(String userId) => _byUserId[userId];

  static String? getForUsername(String username) =>
      _byUsername[username.toLowerCase()];

  static Future<void> setForUserId(String userId, String? url) async {
    _byUserId[userId] = url;
    await _persist();
  }

  static Future<void> setForUsername(String username, String? url) async {
    _byUsername[username.toLowerCase()] = url;
    await _persist();
  }

  static Future<void> clearAll() async {
    _byUserId.clear();
    _byUsername.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userIdKey);
    await prefs.remove(_usernameKey);
  }

  static Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userIdKey, jsonEncode(_byUserId));
      await prefs.setString(_usernameKey, jsonEncode(_byUsername));
    } catch (_) {
      // Ignore cache save failures.
    }
  }
}

