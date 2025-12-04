import 'package:flutter/material.dart';
import 'package:appwrite/models.dart' as aw;

import '../services/appwrite_service.dart';
import '../models/chat.dart';
import 'individual_chat_screen.dart';

class NewChatScreen extends StatefulWidget {
  const NewChatScreen({super.key});

  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<aw.Row> _profiles = <aw.Row>[];
  List<aw.Row> _filteredProfiles = <aw.Row>[];
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _loadProfiles();
    _searchController.addListener(_filterUsers);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadProfiles() async {
    final me = await AppwriteService.getCurrentUser();
    if (me == null) return;
    _currentUserId = me.$id;

    try {
      final aw.RowList list = await AppwriteService.getDocuments(
        AppwriteService.profilesCollectionId,
        queries: [],
      );
      if (!mounted) return;
      setState(() {
        _profiles = list.rows
            .where((row) => (row.data['userId'] as String?) != me.$id)
            .toList();
        _filteredProfiles = List<aw.Row>.from(_profiles);
      });
    } catch (_) {}
  }

  void _filterUsers() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredProfiles = _profiles.where((row) {
        final data = row.data;
        final displayName = (data['displayName'] as String?) ?? '';
        final username = (data['username'] as String?) ?? '';
        return displayName.toLowerCase().contains(query) ||
            username.toLowerCase().contains(query);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Chat'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search for people',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _filteredProfiles.length,
              itemBuilder: (context, index) {
                final row = _filteredProfiles[index];
                final data = row.data;
                final userId = data['userId'] as String? ?? row.$id;
                final displayName = (data['displayName'] as String?) ?? '';
                final username = (data['username'] as String?) ?? '';
                final name =
                    displayName.isNotEmpty ? displayName : (username.isNotEmpty ? username : 'User');
                final avatar = data['avatarUrl'] as String? ?? '';

                return ListTile(
                  leading: CircleAvatar(
                    radius: 26,
                    backgroundColor: const Color(0xFF29ABE2),
                    backgroundImage:
                        avatar.isNotEmpty && avatar.startsWith('http') ? NetworkImage(avatar) : null,
                    child: avatar.isEmpty ? Text(name.isNotEmpty ? name[0] : '?') : null,
                  ),
                  title: Text(name),
                  subtitle: Text('@$username'),
                  onTap: () => _startChatWith(userId, name, avatar),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startChatWith(String partnerId, String partnerName, String avatar) async {
    if (_currentUserId == null) return;
    try {
      final chatId = await AppwriteService.getChatId(_currentUserId!, partnerId);
      // Build a minimal Chat model so the new chat opens immediately;
      // ChatScreen realtime subscription will pick up messages as they arrive.
      final chat = Chat(
        id: chatId,
        partnerId: partnerId,
        partnerName: partnerName,
        partnerAvatar: avatar,
        lastMessage: '',
        timestamp: DateTime.now(),
        unreadCount: 0,
        isOnline: false,
      );
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => IndividualChatScreen(chat: chat)),
      );
    } catch (_) {}
  }
}
