import 'package:shared_preferences/shared_preferences.dart';
import 'appwrite_service.dart';

/// Lightweight helper to capture impression-level ad revenue (ILRD).
/// Tracks totals per ad format so banner/native/rewarded are separated.
class AdRevenueService {
  static const _totalByFormatKey = 'ad_rev_total_by_format';
  static const _countByFormatKey = 'ad_rev_count_by_format';

  /// Record a paid event locally. You can extend this to send to your backend.
  static Future<void> recordPaidEvent({
    required String adUnitId,
    required String format, // e.g. rewarded, banner, native, interstitial
    required String placement,
    required int valueMicros,
    required String? currencyCode,
    required int? precisionType,
    String? countryCode, // ISO 3166-1 alpha-2
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final totals = Map<String, int>.from(
        (prefs.getStringList(_totalByFormatKey)?.asMap().map((_, v) => MapEntry(v.split('|')[0], int.tryParse(v.split('|')[1]) ?? 0)) ?? {}));
    final counts = Map<String, int>.from(
        (prefs.getStringList(_countByFormatKey)?.asMap().map((_, v) => MapEntry(v.split('|')[0], int.tryParse(v.split('|')[1]) ?? 0)) ?? {}));

    totals[format] = (totals[format] ?? 0) + valueMicros;
    counts[format] = (counts[format] ?? 0) + 1;

    await prefs.setStringList(
      _totalByFormatKey,
      totals.entries.map((e) => '${e.key}|${e.value}').toList(),
    );
    await prefs.setStringList(
      _countByFormatKey,
      counts.entries.map((e) => '${e.key}|${e.value}').toList(),
    );

    // Send to Appwrite for server-side payout tracking (best-effort).
    try {
      final user = await AppwriteService.getCurrentUser();
      await AppwriteService.createDocument(
        AppwriteService.adRevenueCollectionId,
        {
          'userId': user?.$id,
          'adUnitId': adUnitId,
          'format': format,
          'placement': placement,
          'valueMicros': valueMicros,
          'currency': currencyCode,
          'country': countryCode,
          'precision': precisionType,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
    } catch (_) {
      // Ignore failures; local tracking still works.
    }
  }

  /// Returns locally accumulated micros per format.
  static Future<Map<String, int>> getTotalsByFormat() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_totalByFormatKey) ?? [];
    final map = <String, int>{};
    for (final entry in raw) {
      final parts = entry.split('|');
      if (parts.length == 2) {
        map[parts[0]] = int.tryParse(parts[1]) ?? 0;
      }
    }
    return map;
  }

  /// Returns event counts per format.
  static Future<Map<String, int>> getCountsByFormat() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_countByFormatKey) ?? [];
    final map = <String, int>{};
    for (final entry in raw) {
      final parts = entry.split('|');
      if (parts.length == 2) {
        map[parts[0]] = int.tryParse(parts[1]) ?? 0;
      }
    }
    return map;
  }
}
