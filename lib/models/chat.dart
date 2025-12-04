class Chat {
  final String id;
  final String partnerId;
  final String partnerName;
  final String partnerAvatar;
  final String lastMessage;
  final DateTime timestamp;
  final int unreadCount;
  final bool isOnline;

  Chat({
    required this.id,
    required this.partnerId,
    required this.partnerName,
    required this.partnerAvatar,
    required this.lastMessage,
    required this.timestamp,
    required this.unreadCount,
    required this.isOnline,
  });
}

class Message {
  final String id;
  final String content;
  final DateTime timestamp;
  final bool isSent;
  final bool isRead;

  Message({
    required this.id,
    required this.content,
    required this.timestamp,
    required this.isSent,
    this.isRead = false,
  });
}
