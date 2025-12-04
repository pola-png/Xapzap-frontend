class Comment {
  final String id;
  final String userId;
  final String username;
  final String userAvatar;
  final String content;
  final DateTime timestamp;

  Comment({
    required this.id,
    required this.userId,
    required this.username,
    required this.userAvatar,
    required this.content,
    required this.timestamp,
  });
}
