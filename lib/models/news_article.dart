class NewsArticle {
  final String id;
  final String title;
  final String? subtitle;
  final String content;
  final String? summary;
  final String? category;
  final List<String> tags;
  final String? topic;
  final String? thumbnailUrl;
  final List<String> imageUrls;
  final String language;
  final String sourceType;
  final bool aiGenerated;
  final DateTime createdAt;

  NewsArticle({
    required this.id,
    required this.title,
    this.subtitle,
    required this.content,
    this.summary,
    this.category,
    this.tags = const <String>[],
    this.topic,
    this.thumbnailUrl,
    this.imageUrls = const <String>[],
    this.language = 'en',
    this.sourceType = 'user',
    this.aiGenerated = false,
    required this.createdAt,
  });
}

