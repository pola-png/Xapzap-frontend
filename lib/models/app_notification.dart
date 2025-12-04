class AppNotification {
  final String id;
  final String title;
  final String body;
  final DateTime timestamp;
  final String? actorName;
  final String? actorAvatar;
  final String? type;

  AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.timestamp,
    this.actorName,
    this.actorAvatar,
    this.type,
  });
}
