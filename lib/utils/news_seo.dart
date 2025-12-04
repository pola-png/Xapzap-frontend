class NewsSeo {
  NewsSeo({
    required this.seoTitle,
    required this.seoDescription,
    required this.seoSlug,
    required this.seoKeywords,
  });

  final String seoTitle;
  final String seoDescription;
  final String seoSlug;
  final List<String> seoKeywords;
}

NewsSeo buildNewsSeo(String rawTitle, String rawContent) {
  final title = rawTitle.trim().isEmpty ? _fallbackTitle(rawContent) : rawTitle.trim();

  final normalized = rawContent.replaceAll('\n', ' ').trim();
  final desc = normalized.length <= 160
      ? normalized
      : '${normalized.substring(0, 157).trimRight()}...';

  final slug = title
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
      .trim()
      .replaceAll(RegExp(r'\s+'), '-');

  final tokens = normalized
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .split(RegExp(r'\s+'))
      .where((t) => t.length >= 4)
      .toList();
  final counts = <String, int>{};
  for (final t in tokens) {
    counts[t] = (counts[t] ?? 0) + 1;
  }
  final sorted = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final keywords = sorted.take(8).map((e) => e.key).toList();

  return NewsSeo(
    seoTitle: title.length > 60 ? '${title.substring(0, 57).trimRight()}...' : title,
    seoDescription: desc,
    seoSlug: slug,
    seoKeywords: keywords,
  );
}

String _fallbackTitle(String content) {
  final trimmed = content.trim();
  if (trimmed.isEmpty) return 'News';
  final firstSentenceEnd = trimmed.indexOf(RegExp(r'[.!?]'));
  if (firstSentenceEnd > 20 && firstSentenceEnd <= 120) {
    return trimmed.substring(0, firstSentenceEnd + 1).trim();
  }
  return trimmed.length <= 80 ? trimmed : '${trimmed.substring(0, 77).trimRight()}...';
}

