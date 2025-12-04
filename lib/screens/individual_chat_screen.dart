import 'package:flutter/material.dart';
import 'package:appwrite/appwrite.dart' show RealtimeSubscription;
import 'package:appwrite/models.dart' as aw;
import '../models/chat.dart';
import '../services/appwrite_service.dart';
import '../services/crypto_service.dart';

class IndividualChatScreen extends StatefulWidget {
  final Chat chat;

  const IndividualChatScreen({super.key, required this.chat});

  @override
  State<IndividualChatScreen> createState() => _IndividualChatScreenState();
}

class _IndividualChatScreenState extends State<IndividualChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Message> _messages = [];
  RealtimeSubscription? _messagesSub;
  String? _currentUserId;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _init();
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
          Expanded(
            child: _buildMessageArea(),
          ),
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF111B21) : theme.colorScheme.surface;
    final textColor = theme.colorScheme.onSurface;
    final subtitleColor = isDark ? const Color(0xFF8696A0) : const Color(0xFF6B7280);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 44, 12, 12), // p-3 with top padding for status bar
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
        children: [
          // Back Button - h-9 w-9 (36px)
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.arrow_back,
                size: 20, // h-5 w-5
                color: textColor,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Chat Partner Info
          Container(
            width: 40, // h-10 w-10
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF29ABE2),
              image: DecorationImage(
                image: NetworkImage(widget.chat.partnerAvatar),
                fit: BoxFit.cover,
                onError: (exception, stackTrace) {},
              ),
            ),
            child: const Icon(Icons.person, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.chat.partnerName,
                  style: TextStyle(
                    fontSize: 16, // text-base
                    fontWeight: FontWeight.w600, // font-semibold
                    color: textColor,
                  ),
                ),
                Text(
                  widget.chat.isOnline ? 'Online' : 'Last seen recently',
                  style: TextStyle(
                    fontSize: 12, // text-xs
                    color: subtitleColor, // text-muted-foreground
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.videocam),
            color: textColor,
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Video calling coming soon')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.call),
            color: textColor,
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Voice calling coming soon')),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMessageArea() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0B141A) : theme.colorScheme.background;
    return Container(
      color: bg,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        itemCount: _messages.length,
        itemBuilder: (context, index) {
          final message = _messages[index];
          return _buildMessageBubble(message);
        },
      ),
    );
  }

  Widget _buildMessageBubble(Message message) {
    final isSent = message.isSent;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bubbleColor = isSent
        ? (isDark ? const Color(0xFF005C4B) : theme.colorScheme.primary.withOpacity(0.12))
        : (isDark ? const Color(0xFF202C33) : theme.colorScheme.surfaceVariant);
    final textColor = isDark
        ? Colors.white
        : (isSent ? theme.colorScheme.primary : theme.colorScheme.onSurface);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 4), // my-2
      child: Row(
        mainAxisAlignment: isSent
          ? MainAxisAlignment.end // justify-end
          : MainAxisAlignment.start, // justify-start
        children: [
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isSent ? 16 : 2),
                bottomRight: Radius.circular(isSent ? 2 : 16),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  message.content,
                  style: TextStyle(
                    fontSize: 16,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatMessageTimestamp(message.timestamp),
                  style: TextStyle(
                    fontSize: 11,
                    color: textColor.withOpacity(isDark ? 0.7 : 0.8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatMessageTimestamp(DateTime ts) {
    final local = ts.toLocal();
    var hour = local.hour;
    final minute = local.minute.toString().padLeft(2, '0');
    final ampm = hour >= 12 ? 'PM' : 'AM';
    hour = hour % 12;
    if (hour == 0) hour = 12;
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final dateStr = '${months[local.month - 1]} ${local.day}, ${local.year}';
    return '$hour:$minute $ampm · $dateStr';
  }

  Widget _buildMessageInput() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF202C33) : Colors.white;
    final fieldBg = isDark ? const Color(0xFF2A3942) : const Color(0xFFF9FAFB);

    return Container(
      padding: const EdgeInsets.all(8), // p-2
      decoration: BoxDecoration(
        color: bg,
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF202C33) : const Color(0xFFE5E7EB),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Emoji/Smiley Button
          IconButton(
            onPressed: () {},
            icon: const Icon(
              Icons.sentiment_satisfied_alt_outlined,
              size: 24,
              color: Color(0xFF8696A0),
            ),
          ),
          // Text Input
          Expanded(
            child: TextField(
              controller: _messageController,
              maxLines: null,
              decoration: InputDecoration(
                hintText: 'Type a message...',
                hintStyle: const TextStyle(color: Color(0xFF8696A0)),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(color: isDark ? Colors.transparent : const Color(0xFFE5E7EB)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(color: isDark ? Colors.transparent : const Color(0xFFE5E7EB)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(color: isDark ? Colors.transparent : const Color(0xFF1DA1F2)),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                filled: true,
                fillColor: fieldBg,
              ),
              onChanged: (value) => setState(() {}),
              style: TextStyle(color: isDark ? Colors.white : Colors.black),
            ),
          ),
          // Attachment Button
          IconButton(
            onPressed: () {},
            icon: const Icon(
              Icons.attach_file,
              size: 24,
              color: Color(0xFF8696A0),
            ),
          ),
          // Send/Voice Button
          GestureDetector(
            onTap: _messageController.text.trim().isNotEmpty ? _sendMessage : null,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF00A884),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _messageController.text.trim().isNotEmpty 
                  ? Icons.send
                  : Icons.mic,
                size: 20,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _init() async {
    final me = await AppwriteService.getCurrentUser();
    if (me == null) return;
    _currentUserId = me.$id;
    await _loadMessages();
    _subscribeMessages();
  }

  String get _chatId => widget.chat.id;

  Future<void> _loadMessages() async {
    if (_currentUserId == null) return;
    try {
      final aw.RowList list =
          await AppwriteService.fetchMessagesForChat(_chatId, limit: 200);
      final msgs = <Message>[];
      for (final row in list.rows) {
        final data = row.data;
        final cipher = data['ciphertext'] as String? ?? '';
        final nonce = data['nonce'] as String? ?? '';
        final fallbackText = (data['content'] as String?) ?? '';
        String text = fallbackText;
        if (cipher.isNotEmpty && nonce.isNotEmpty) {
          final dec = await CryptoService.decryptMessage(
            chatId: _chatId,
            partnerUserId: widget.chat.partnerId,
            ciphertextB64: cipher,
            nonceB64: nonce,
          );
          if (dec != null && dec.isNotEmpty) {
            text = dec;
          }
        }
        final senderId = (data['senderId'] as String?) ?? '';
        final createdAtStr =
            data['timestamp'] as String? ?? data['createdAt'] as String?;
        final createdAt =
            DateTime.tryParse(createdAtStr ?? '') ?? DateTime.now();
        final rawReadBy = (data['readBy'] as String?) ?? '';
        final readBy = rawReadBy
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
        final isRead = readBy.contains(_currentUserId);
        msgs.add(
          Message(
            id: row.$id,
            content: text,
            timestamp: createdAt,
            isSent: senderId == _currentUserId,
            isRead: isRead,
          ),
        );
      }
      msgs.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(msgs);
      });
      await _markMessagesRead();
      _scrollToBottom();
    } catch (_) {}
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  void _subscribeMessages() {
    final channel =
        'databases.${AppwriteService.databaseId}.collections.${AppwriteService.messagesCollectionId}.documents';
    try {
      _messagesSub = AppwriteService.realtime.subscribe([channel]);
      _messagesSub?.stream.listen((event) async {
        if (!mounted) return;
        if (event.events.isEmpty) return;
        final payload = event.payload;
        if (payload['chatId'] != _chatId) return;
        await _loadMessages();
      });
    } catch (_) {}
  }

  Future<void> _markMessagesRead() async {
    if (_currentUserId == null) return;
    try {
      final aw.RowList list =
          await AppwriteService.fetchMessagesForChat(_chatId, limit: 200);
      for (final row in list.rows) {
        final data = row.data;
        final senderId = (data['senderId'] as String?) ?? '';
        if (senderId == _currentUserId) continue;
        final rawReadBy = (data['readBy'] as String?) ?? '';
        final readBySet = rawReadBy.isEmpty
            ? <String>{}
            : rawReadBy.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
        if (readBySet.contains(_currentUserId)) continue;
        readBySet.add(_currentUserId!);
        await AppwriteService.updateRow(
          AppwriteService.messagesCollectionId,
          row.$id,
          {
            ...data,
            'readBy': readBySet.join(','),
            'isRead': true,
          },
        );
      }
    } catch (_) {}
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _currentUserId == null || _isSending) return;
    setState(() => _isSending = true);
    final now = DateTime.now();
    final optimistic = Message(
      id: 'local-${now.microsecondsSinceEpoch}',
      content: text,
      timestamp: now,
      isSent: true,
      isRead: true,
    );
    setState(() {
      _messages.add(optimistic);
    });
    _messageController.clear();
    _scrollToBottom();
    try {
      final enc = await CryptoService.encryptMessage(
        chatId: _chatId,
        partnerUserId: widget.chat.partnerId,
        plaintext: text,
      );

      await AppwriteService.createDocument(
        AppwriteService.messagesCollectionId,
        {
          'chatId': _chatId,
          'senderId': _currentUserId,
          'content': text,
          'ciphertext': enc?['ciphertext'],
          'nonce': enc?['nonce'],
          'timestamp': DateTime.now().toIso8601String(),
          'isRead': false,
          'isEdited': false,
          // Store readBy as comma-separated string (schema uses string column).
          'readBy': _currentUserId,
        },
      );
      await AppwriteService.updateRow(
        AppwriteService.chatsCollectionId,
        _chatId,
        {
          'lastMessage': text,
          'lastCiphertext': enc?['ciphertext'],
          'lastNonce': enc?['nonce'],
          'lastSenderId': _currentUserId,
          'lastMessageAt': DateTime.now().toIso8601String(),
          'timestamp': DateTime.now().toIso8601String(),
          'unreadCount': 0,
        },
      );
      await _loadMessages();
    } catch (_) {
      if (mounted) {
        setState(() {
          _messages.removeWhere((m) => m.id == optimistic.id);
          _messageController.text = text;
        });
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  void dispose() {
    _messagesSub?.close();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}
