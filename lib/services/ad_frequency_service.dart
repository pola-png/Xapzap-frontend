import 'package:shared_preferences/shared_preferences.dart';

/// Tracks rewarded ad frequency per video.
class AdFrequencyService {
  static const _rewardedPrefix = 'ad_last_rewarded_';
  static const Duration rewardedCooldown = Duration(hours: 5);

  /// Returns true if a rewarded ad should be shown for [videoId].
  static Future<bool> shouldShowRewarded(String videoId) async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt('$_rewardedPrefix$videoId');
    if (last == null) return true;
    final elapsedMs = DateTime.now().millisecondsSinceEpoch - last;
    return elapsedMs > rewardedCooldown.inMilliseconds;
  }

  /// Records that a rewarded ad was shown for [videoId].
  static Future<void> markRewarded(String videoId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_rewardedPrefix + videoId, DateTime.now().millisecondsSinceEpoch);
  }
}
