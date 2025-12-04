import 'package:flutter/material.dart';
import 'package:appwrite/appwrite.dart' show RealtimeSubscription;
import 'package:lucide_icons/lucide_icons.dart';
import '../screens/home_screen.dart';
import '../screens/chat_screen.dart';
import '../screens/notifications_screen.dart';
import '../screens/profile_screen.dart';
import '../models/upload_type.dart';
import '../screens/upload_screen.dart';
import '../services/appwrite_service.dart';
import '../screens/auth/sign_in_screen.dart';
import '../screens/search_screen.dart';
import '../screens/banned_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  bool _isAuthed = false;
  int _unreadChats = 0;
  int _unreadNotifications = 0;
  RealtimeSubscription? _badgeSub;
  RealtimeSubscription? _banSub;
  String? _avatarUrl;
  bool _banHandled = false;

  final List<Widget> _screens = [
    const HomeScreen(),
    const ChatScreen(),
    const SizedBox.shrink(),
    const NotificationsScreen(),
    const ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _checkAuth();
    _loadBadges();
    _subscribeBadges();
    _subscribeBanWatcher();
  }

  Future<void> _checkAuth() async {
    final user = await AppwriteService.getCurrentUser();
    if (!mounted) return;
    if (user == null) {
      setState(() {
        _isAuthed = false;
        _avatarUrl = null;
      });
      return;
    }
    String? avatar;
    try {
      final profile = await AppwriteService.getProfileByUserId(user.$id);
      avatar = profile?.data['avatarUrl'] as String?;
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _isAuthed = true;
      _avatarUrl = avatar;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth > 1100;
        return Scaffold(
          appBar: isDesktop
              ? AppBar(
                  toolbarHeight: 64,
                  titleSpacing: 0,
                  leadingWidth: 0,
                  automaticallyImplyLeading: false,
                  leading: const SizedBox.shrink(),
                  title: Row(
                    children: [
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          'XapZap',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Wrap(
                          spacing: 28,
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _buildNavAction(0, LucideIcons.home, null),
                            _buildNavAction(
                              1,
                              LucideIcons.messageCircle,
                              _unreadChats > 0 ? '$_unreadChats' : null,
                            ),
                            _buildNavAction(2, LucideIcons.plusSquare, null),
                            _buildNavAction(
                              3,
                              LucideIcons.bell,
                              _unreadNotifications > 0
                                  ? '$_unreadNotifications'
                                  : null,
                            ),
                            _buildNavAction(4, LucideIcons.user, null),
                          ],
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    IconButton(
                      icon: const Icon(LucideIcons.search),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const SearchScreen(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 4),
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: CircleAvatar(
                        radius: 16,
                        backgroundColor: Colors.grey.shade300,
                        backgroundImage:
                            (_avatarUrl != null && _avatarUrl!.isNotEmpty)
                            ? NetworkImage(_avatarUrl!)
                            : null,
                        child: (_avatarUrl == null || _avatarUrl!.isEmpty)
                            ? const Icon(
                                LucideIcons.user,
                                size: 16,
                                color: Colors.black54,
                              )
                            : null,
                      ),
                    ),
                  ],
                )
              : null,
          // Keep all tab screens alive using an IndexedStack so that
          // Home, Chats, Updates and Profile preserve their state and
          // do not rebuild when switching tabs.
          body: IndexedStack(index: _currentIndex, children: _screens),
          bottomNavigationBar: isDesktop
              ? null
              : Container(
                  height: 64,
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    border: const Border(
                      top: BorderSide(color: Color(0xFFE5E7EB), width: 1),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildNavItem(0, LucideIcons.home, null),
                      _buildNavItem(
                        1,
                        LucideIcons.messageCircle,
                        _unreadChats > 0 ? '$_unreadChats' : null,
                      ),
                      _buildNavItem(2, LucideIcons.plusSquare, null),
                      _buildNavItem(
                        3,
                        LucideIcons.bell,
                        _unreadNotifications > 0
                            ? '$_unreadNotifications'
                            : null,
                      ),
                      _buildNavItem(4, LucideIcons.user, null),
                    ],
                  ),
                ),
        );
      },
    );
  }

  Widget _buildNavItem(int index, IconData icon, String? badge) {
    final isActive = _currentIndex == index;
    return GestureDetector(
      onTap: () async {
        final requiresAuth = index != 0;
        if (requiresAuth && !_isAuthed) {
          final proceed = await _redirectToSignIn();
          if (!proceed) return;
        }
        if (index == 2) {
          if (!_isAuthed) return;
          _showCreatePicker();
        } else {
          setState(() => _currentIndex = index);
        }
      },
      child: Container(
        padding: const EdgeInsets.all(8),
        child: Stack(
          children: [
            Icon(
              icon,
              size: 28,
              color: isActive ? const Color(0xFF29ABE2) : Colors.grey[600],
            ),
            if (badge != null)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      badge,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavAction(int index, IconData icon, String? badge) {
    final isActive = _currentIndex == index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton(
            iconSize: 26,
            icon: Icon(icon, color: isActive ? const Color(0xFF29ABE2) : null),
            onPressed: () async {
              final requiresAuth = index != 0;
              if (requiresAuth && !_isAuthed) {
                final proceed = await _redirectToSignIn();
                if (!proceed) return;
              }
              if (index == 2) {
                if (!_isAuthed) return;
                _showCreatePicker();
              } else {
                setState(() => _currentIndex = index);
              }
            },
          ),
          if (badge != null)
            Positioned(
              right: 4,
              top: 6,
              child: Container(
                width: 16,
                height: 16,
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    badge,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<bool> _redirectToSignIn() async {
    if (!mounted) return false;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SignInScreen()));
    if (!mounted) return false;
    await _checkAuth();
    return _isAuthed;
  }

  void _showCreatePicker() {
    showModalBottomSheet<UploadType>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              const Text(
                'Create',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(LucideIcons.image),
                title: const Text('Image / Text'),
                onTap: () => Navigator.of(ctx).pop(UploadType.standard),
              ),
              ListTile(
                leading: const Icon(LucideIcons.video),
                title: const Text('Video'),
                onTap: () => Navigator.of(ctx).pop(UploadType.video),
              ),
              ListTile(
                leading: const Icon(LucideIcons.playCircle),
                title: const Text('Reel'),
                onTap: () => Navigator.of(ctx).pop(UploadType.reel),
              ),
              ListTile(
                leading: const Icon(LucideIcons.newspaper),
                title: const Text('News / Blog'),
                onTap: () => Navigator.of(ctx).pop(UploadType.news),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    ).then((type) {
      if (type == null) return;
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => UploadScreen(type: type)));
    });
  }

  Future<void> _loadBadges() async {
    final user = await AppwriteService.getCurrentUser();
    if (user == null) return;
    // Unread chats: count messages in chats not sent by me and not marked read.
    try {
      final chats = await AppwriteService.fetchChatsForUser(user.$id);
      int unreadChatCount = 0;
      for (final chatRow in chats.rows) {
        final rawMemberIds = (chatRow.data['memberIds'] as String?) ?? '';
        final memberIds = rawMemberIds
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
        final partnerId = memberIds.firstWhere(
          (id) => id != user.$id,
          orElse: () => '',
        );
        if (partnerId.isEmpty) continue;
        final msgs = await AppwriteService.fetchMessagesForChat(
          chatRow.$id,
          limit: 30,
        );
        for (final m in msgs.rows) {
          final data = m.data;
          final senderId = (data['senderId'] as String?) ?? '';
          if (senderId == user.$id) continue;
          final rawReadBy = (data['readBy'] as String?) ?? '';
          final readBy = rawReadBy
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty);
          if (!readBy.contains(user.$id)) {
            unreadChatCount++;
          }
        }
      }
      final notifs = await AppwriteService.fetchNotifications(
        user.$id,
        limit: 50,
      );
      if (!mounted) return;
      setState(() {
        _unreadChats = unreadChatCount.clamp(0, 99);
        _unreadNotifications = notifs.length.clamp(0, 99);
      });
    } catch (_) {
      // ignore failures
    }
  }

  void _subscribeBadges() {
    try {
      final channelMessages =
          'databases.${AppwriteService.databaseId}.collections.${AppwriteService.messagesCollectionId}.documents';
      final channelNotifs =
          'databases.${AppwriteService.databaseId}.collections.${AppwriteService.notificationsCollectionId}.documents';
      _badgeSub = AppwriteService.realtime.subscribe([
        channelMessages,
        channelNotifs,
      ]);
      _badgeSub?.stream.listen((event) async {
        if (!mounted) return;
        if (event.events.isEmpty) return;
        // Any create/update/delete affecting messages or notifications should refresh badges.
        await _loadBadges();
      });
    } catch (_) {}
  }

  void _subscribeBanWatcher() async {
    try {
      final user = await AppwriteService.getCurrentUser();
      if (user == null) return;
      final channelProfile =
          'databases.${AppwriteService.databaseId}.collections.${AppwriteService.profilesCollectionId}.documents.${user.$id}';
      _banSub = AppwriteService.realtime.subscribe([channelProfile]);
      _banSub?.stream.listen((event) async {
        if (!mounted || _banHandled) return;
        // Any change to the profile should re-check ban status.
        final banned = await AppwriteService.isUserBanned(user.$id);
        if (!banned) return;
        _banHandled = true;
        try {
          await AppwriteService.signOut();
        } catch (_) {}
        if (!mounted) return;
        // Kick the user out of the app and show banned screen.
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const BannedScreen()),
          (route) => false,
        );
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _badgeSub?.close();
    _banSub?.close();
    super.dispose();
  }
}
