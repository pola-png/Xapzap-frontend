class Post {
  final String id;
  final String username;
  final String userAvatar;
  final String content;
  final String? imageUrl;
  final String? videoUrl;
  final String? kind;
  final String? title;
  final String? thumbnailUrl;
  final DateTime timestamp;
  final int likes;
  final int comments;
  final int reposts;
  final int impressions;
  final int views;
  final bool isLiked;
  final bool isReposted;
  final bool isSaved;
  final String? sourcePostId;
  final String? sourceUserId;
  final String? sourceUsername;
  final int? textBgColor;
  final bool isBoosted;
  final String? activeBoostId;

  Post({
    required this.id,
    required this.username,
    required this.userAvatar,
    required this.content,
    this.imageUrl,
    this.videoUrl,
    this.kind,
    this.title,
    this.thumbnailUrl,
    required this.timestamp,
    required this.likes,
    required this.comments,
    this.reposts = 0,
    this.impressions = 0,
    this.views = 0,
    this.isLiked = false,
    this.isReposted = false,
    this.isSaved = false,
    this.sourcePostId,
    this.sourceUserId,
    this.sourceUsername,
    this.textBgColor,
    this.isBoosted = false,
    this.activeBoostId,
  });

  int get totalEngagement => likes + comments + reposts + impressions + views;
}
