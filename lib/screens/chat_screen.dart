import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:appwrite/appwrite.dart' show RealtimeSubscription;
import 'package:appwrite/models.dart' as aw;
import '../models/chat.dart';
import '../services/appwrite_service.dart';
import '../services/storage_service.dart';
import '../services/crypto_service.dart';
import 'individual_chat_screen.dart';
import 'new_chat_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Chat> _chats = <Chat>[];
  List<Chat> _filteredChats = [];
  RealtimeSubscription? _messagesSub;

  @override
  void initState() {
    super.initState();
    _loadChats();
    _subscribeMessages();
    _searchController.addListener(() {
      filterChats();
    });
  }

  @override
  void dispose() {
    _messagesSub?.close();
    _searchController.dispose();
    super.dispose();
  }

  void filterChats() {
    String query = _searchController.text.toLowerCase();
    setState(() {
      _filteredChats = _chats
          .where((chat) => chat.partnerName.toLowerCase().contains(query))
          .toList();
    });
  }

  Future<void> _loadChats() async {
    final me = await AppwriteService.getCurrentUser();
    if (me == null) return;

    try {
      final aw.RowList list = await AppwriteService.fetchChatsForUser(me.$id);
      final chats = <Chat>[];
      for (final row in list.rows) {
        final chat = await _buildChatFromRow(row, me.$id);
        if (chat != null) {
          chats.add(chat);
        }
      }
      if (!mounted) return;
      setState(() {
        _chats = chats;
        filterChats();
      });
    } catch (_) {
      // Ignore errors; leave list empty.
    }
  }

  Future<Chat?> _buildChatFromRow(aw.Row row, String meId) async {
    final data = row.data;
    // memberIds is stored as a comma-separated string.
    final rawIds = (data['memberIds'] as String?) ?? '';
    final userIds = rawIds
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (userIds.length < 2) return null;
    final partnerId = userIds.firstWhere((id) => id != meId, orElse: () => meId);
    if (partnerId == meId) return null;

    // Load partner profile for name/avatar.
    final prof = await AppwriteService.getProfileByUserId(partnerId);
    final pdata = prof?.data ?? <String, dynamic>{};
    final displayName = (pdata['displayName'] as String?)?.trim();
    final username = (pdata['username'] as String?)?.trim();
    String partnerName = displayName?.isNotEmpty == true
        ? displayName!
        : (username?.isNotEmpty == true ? username! : 'User');

    String avatar = pdata['avatarUrl'] as String? ?? '';
    if (avatar.isNotEmpty && !avatar.startsWith('http')) {
      try {
        avatar = await WasabiService.getSignedUrl(avatar);
      } catch (_) {}
    }

    // Load last message & unread count.
    final aw.RowList msgs =
        await AppwriteService.fetchMessagesForChat(row.$id, limit: 50);
    String lastText = '';
    DateTime lastTime = DateTime.fromMillisecondsSinceEpoch(0);
    int unread = 0;

    for (final m in msgs.rows) {
      final mdata = m.data;
      final cipher = mdata['ciphertext'] as String? ?? '';
      final nonce = mdata['nonce'] as String? ?? '';
      final fallbackText = (mdata['content'] as String?) ?? '';
      String text = fallbackText;
      if (cipher.isNotEmpty && nonce.isNotEmpty) {
        final dec = await CryptoService.decryptMessage(
          chatId: row.$id,
          partnerUserId: partnerId,
          ciphertextB64: cipher,
          nonceB64: nonce,
        );
        if (dec != null && dec.isNotEmpty) {
          text = dec;
        }
      }
      final senderId = (mdata['senderId'] as String?) ?? '';
      final createdAtStr = mdata['timestamp'] as String? ?? mdata['createdAt'] as String?;
      final createdAt = DateTime.tryParse(createdAtStr ?? '') ?? DateTime.now();

      if (text.isNotEmpty && createdAt.isAfter(lastTime)) {
        lastText = text;
        lastTime = createdAt;
      }

      final rawReadBy = (mdata['readBy'] as String?) ?? '';
      final readBy = rawReadBy.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      final isRead = readBy.contains(meId);
      if (senderId != meId && !isRead) {
        unread++;
      }
    }

    if (lastTime.millisecondsSinceEpoch == 0 && msgs.rows.isEmpty) {
      lastTime = DateTime.now();
    }

    return Chat(
      id: row.$id,
      partnerId: partnerId,
      partnerName: partnerName,
      partnerAvatar: avatar,
      lastMessage: lastText,
      timestamp: lastTime,
      unreadCount: unread,
      isOnline: false,
    );
  }

  void _subscribeMessages() {
    final channel =
        'databases.${AppwriteService.databaseId}.collections.${AppwriteService.messagesCollectionId}.documents';
    try {
      _messagesSub = AppwriteService.realtime.subscribe([channel]);
      _messagesSub?.stream.listen((event) async {
        if (!mounted) return;
        if (event.events.isEmpty) return;
        final name = event.events.first;
        if (name.contains('.create') || name.contains('.update')) {
          await _loadChats();
        }
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF111B21) : Colors.white;

    return Scaffold(
      backgroundColor: bg,
      body: Column(
        children: [
          _buildHeader(),
          _buildSearchBar(),
          Expanded(
            child: _buildChatList(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF111B21) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black;

    return Container(
      height: 56, // h-14
      padding: const EdgeInsets.symmetric(horizontal: 16), // px-4
      decoration: BoxDecoration(
        color: bg,
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF202C33) : const Color(0xFFE5E7EB),
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween, // justify-between
        children: [
          Text(
            'Chats',
            style: TextStyle(
              fontSize: 24, // text-2xl
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          IconButton(
            onPressed: _startNewChat,
            icon: Icon(
              LucideIcons.edit,
              size: 24,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF111B21) : Colors.white;
    final fieldBg = isDark ? const Color(0xFF202C33) : const Color(0xFFF9FAFB);
    final hintColor = isDark ? const Color(0xFF8696A0) : const Color(0xFF6B7280);

    return Container(
      padding: const EdgeInsets.all(16),
      color: bg,
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search chats',
          hintStyle: TextStyle(color: hintColor),
          prefixIcon: Icon(LucideIcons.search, color: hintColor),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide(
              color: isDark ? const Color(0xFF202C33) : const Color(0xFFE5E7EB),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide(
              color: isDark ? const Color(0xFF202C33) : const Color(0xFFE5E7EB),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide(
              color: isDark ? const Color(0xFF00A884) : const Color(0xFF29ABE2),
            ),
          ),
          filled: true,
          fillColor: fieldBg,
        ),
        style: TextStyle(color: isDark ? Colors.white : Colors.black),
      ),
    );
  }

  Widget _buildChatList() {
    return ListView.separated(
      itemCount: _filteredChats.length,
      separatorBuilder: (context, index) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        return Divider(
          height: 0,
          thickness: 0.6,
          indent: 76,
          color: isDark ? const Color(0xFF202C33) : const Color(0xFFE5E7EB),
        );
      },
      itemBuilder: (context, index) {
        final chat = _filteredChats[index];
        return _buildChatItem(chat);
      },
    );
  }

  Widget _buildChatItem(Chat chat) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF111B21) : Colors.white;
    final titleColor = isDark ? Colors.white : Colors.black;
    final subtitleColor = isDark ? const Color(0xFF8696A0) : const Color(0xFF6B7280);
    final timeColor = subtitleColor;

    return GestureDetector(
      onTap: () => _navigateToChat(chat),
      child: Container(
        padding: const EdgeInsets.all(16), // p-4
        color: bg,
        child: Row(
          children: [
            // User Avatar - h-12 w-12 (48px)
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF29ABE2),
                image: DecorationImage(
                  image: NetworkImage(chat.partnerAvatar),
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(width: 12), // space-x-3
            // Chat Details - flex-1 min-w-0
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    chat.partnerName,
                    style: TextStyle(
                      fontSize: 16, // text-base
                      fontWeight: FontWeight.w500, // font-medium
                      color: titleColor,
                    ),
                    overflow: TextOverflow.ellipsis, // truncate
                  ),
                  const SizedBox(height: 2),
                  Text(
                    chat.lastMessage,
                    style: TextStyle(
                      fontSize: 14, // text-sm
                      color: subtitleColor, // text-muted-foreground
                    ),
                    overflow: TextOverflow.ellipsis, // truncate
                  ),
                ],
              ),
            ),
            // Timestamp & Status
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _formatTimestamp(chat.timestamp),
                  style: TextStyle(
                    fontSize: 12, // text-xs
                    color: timeColor, // text-muted-foreground
                  ),
                ),
                if (chat.unreadCount > 0) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: const BoxDecoration(
                      color: Color(0xFF29ABE2), // bg-primary
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${chat.unreadCount}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inDays > 0) {
      return '${difference.inDays}d';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m';
    } else {
      return 'now';
    }
  }

  void _startNewChat() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const NewChatScreen()),
    );
  }

  void _navigateToChat(Chat chat) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => IndividualChatScreen(chat: chat),
      ),
    );
  }
}
