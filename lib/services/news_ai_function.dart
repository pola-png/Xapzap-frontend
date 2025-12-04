import 'dart:convert';

import 'package:appwrite/appwrite.dart';

import 'appwrite_service.dart';

/// Helper to call the AI News Appwrite Function from the client.
class NewsAiFunction {
  /// Appwrite Function ID for `news-ai`.
  static const String functionId = '6931ff060021e3d13256';

  /// Triggers the news AI function to generate an article for [topic].
  ///
  /// [language] is an ISO language code like "en", "fr", "es".
  /// Optional trend metadata can be provided to classify the article.
  ///
  /// Returns the parsed JSON response from the function, or `null` on failure.
  static Future<Map<String, dynamic>?> generateNews({
    required String topic,
    String language = 'en',
    String? trendType,
    double? trendScore,
    List<String>? trendSource,
    int? trendWindowMinutes,
  }) async {
    final client = AppwriteService.account.client;
    final functions = Functions(client);

    final payload = <String, dynamic>{
      'topic': topic,
      'language': language,
      if (trendType != null) 'trendType': trendType,
      if (trendScore != null) 'trendScore': trendScore,
      if (trendSource != null && trendSource.isNotEmpty)
        'trendSource': trendSource,
      if (trendWindowMinutes != null)
        'trendWindowMinutes': trendWindowMinutes,
    };

    final execution = await functions.createExecution(
      functionId: functionId,
      body: jsonEncode(payload),
    );

    if (execution.responseBody.isEmpty) return null;
    try {
      final decoded =
          jsonDecode(execution.responseBody) as Map<String, dynamic>;
      return decoded;
    } catch (_) {
      return null;
    }
  }
}

