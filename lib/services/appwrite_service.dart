import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appwrite/appwrite.dart';
import 'package:crypto/crypto.dart';
import 'package:appwrite/models.dart' as models;
import 'package:appwrite/enums.dart' as enums;
import 'package:flutter/foundation.dart';
import '../config/environment.dart';
import '../models/status.dart';
import '../models/app_notification.dart';
import 'storage_service.dart';

class AppwriteService {
  static const String endpoint = Environment.appwritePublicEndpoint;
  static const String projectId = Environment.appwriteProjectId;
  static const String databaseId = 'xapzap_db';

  // Collections
  static const String usersCollectionId = 'users';
  static const String postsCollectionId = 'posts';
  static const String commentsCollectionId = 'comments';
  static const String profilesCollectionId = 'profiles';
  static const String followsCollectionId = 'follows';
  static const String likesCollectionId = 'likes';
  static const String commentLikesCollectionId = 'comment_likes';
  static const String repostsCollectionId = 'reposts';
  static const String reportsCollectionId = 'reports';
  static const String savesCollectionId = 'saves';
  static const String chatsCollectionId = 'chats';
  static const String messagesCollectionId = 'messages';
  static const String statusesCollectionId = 'statuses';
  static const String notificationsCollectionId = 'notifications';
  static const String postBoostsCollectionId = 'post_boosts';
  static const String newsCollectionId = 'news';
  static const String adRevenueCollectionId = 'ad_revenue_events';

  // Buckets
  // Appwrite bucket ID for media uploads
  static const String mediaBucketId = '6915baaa00381391d7b2';

  static late Client _client;
  static late Account _account;
  static late TablesDB _tables;
  static late Storage _storage;
  static late Realtime _realtime;

  static Realtime get realtime => _realtime;

  static Account get account => _account;

  // Follow graph change notifier
  static final ValueNotifier<int> followingVersion = ValueNotifier<int>(0);

  static Future<void> initialize() async {
    _client = Client().setEndpoint(endpoint).setProject(projectId);
    _account = Account(_client);
    _tables = TablesDB(_client);
    _storage = Storage(_client);
    _realtime = Realtime(_client);
  }

  static bool? _isAdminCache;
  static bool? _isBannedCache;

  static void _resetAuthCaches() {
    _isAdminCache = null;
    _isBannedCache = null;
  }

  static Future<models.User> getAccount() {
    return _account.get();
  }

  static Future<models.File> uploadFile(
    String bucketId,
    File file,
    String fileId,
  ) async {
    try {
      return await _storage.createFile(
        bucketId: bucketId,
        fileId: fileId,
        file: InputFile.fromPath(path: file.path),
      );
    } on AppwriteException catch (e) {
      // Fallback for cases where the SDK sees an "empty" file path (e.g. some video sources).
      if (e.code == 400 &&
          (e.type == 'storage_file_empty' ||
              (e.message ?? '').contains('storage_file_empty'))) {
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) rethrow;
        return await _storage.createFile(
          bucketId: bucketId,
          fileId: fileId,
          file: InputFile.fromBytes(bytes: bytes, filename: fileId),
        );
      }
      rethrow;
    }
  }

  static String buildFileViewUrl(String bucketId, String fileId) {
    // endpoint already includes /v1
    return '$endpoint/storage/buckets/$bucketId/files/$fileId/view?project=$projectId&mode=public';
  }

  // Generic TablesDB helpers
  static Future<models.Row> getRow(String tableId, String rowId) {
    return _tables.getRow(
      databaseId: databaseId,
      tableId: tableId,
      rowId: rowId,
    );
  }

  static Future<models.Row> updateRow(
    String tableId,
    String rowId,
    Map<String, dynamic> data,
  ) {
    return _tables.updateRow(
      databaseId: databaseId,
      tableId: tableId,
      rowId: rowId,
      data: data,
    );
  }

  static Future<String> getChatId(String userId1, String userId2) async {
    final sortedIds = [userId1, userId2]..sort();
    // Appwrite rowId max length is 36 chars; hash the pair to keep it short yet deterministic.
    final chatId = _hashId(sortedIds.join('_'));
    final memberIdsValue = sortedIds.join(',');

    try {
      await _tables.getRow(
        databaseId: databaseId,
        tableId: chatsCollectionId,
        rowId: chatId,
      );
    } catch (e) {
      if (e is AppwriteException && e.code == 404) {
        await _tables.createRow(
          databaseId: databaseId,
          tableId: chatsCollectionId,
          rowId: chatId,
          data: {
            'chatId': chatId,
            // memberIds is a single string column; store as comma-separated list.
            'memberIds': memberIdsValue,
            'createdAt': DateTime.now().toIso8601String(),
          },
        );
      } else {
        rethrow;
      }
    }
    try {
      await _tables.updateRow(
        databaseId: databaseId,
        tableId: chatsCollectionId,
        rowId: chatId,
        data: {'memberIds': memberIdsValue},
      );
    } catch (_) {}
    return chatId;
  }

  static String _hashId(String input) {
    // 32-char md5 hex fits Appwrite UID requirements (a-z, A-Z, 0-9, underscore) and length <= 36.
    return md5.convert(utf8.encode(input)).toString();
  }

  // Auth
  static Future<models.User> signUp(
    String email,
    String password,
    String username,
  ) async {
    await _account.create(
      userId: ID.unique(),
      email: email,
      password: password,
      name: username,
    );
    await signIn(email, password);
    final createdUser = await _account.get();
    await _tables.createRow(
      databaseId: databaseId,
      tableId: usersCollectionId,
      rowId: createdUser.$id,
      data: {'userId': createdUser.$id, 'username': username, 'email': email},
    );
    return createdUser;
  }

  static Future<models.Session> signIn(String email, String password) async =>
      _account.createEmailPasswordSession(email: email, password: password);

  static Future<void> signInWithGoogle() async => AppwriteService.account
      .createOAuth2Session(provider: enums.OAuthProvider.google);

  static Future<void> signOut() async {
    _resetAuthCaches();
    await _account.deleteSession(sessionId: 'current');
  }

  static Future<models.User?> getCurrentUser() async {
    try {
      return await _account.get();
    } catch (_) {
      return null;
    }
  }

  static Future<bool> isCurrentUserAdmin() async {
    if (_isAdminCache != null) return _isAdminCache!;
    final user = await getCurrentUser();
    if (user == null) {
      _isAdminCache = false;
      return false;
    }
    try {
      final prof = await getProfileByUserId(user.$id);
      final raw = prof?.data['isAdmin'];
      final val = raw is bool
          ? raw
          : (raw is String ? (raw.toLowerCase() == 'true') : false);
      _isAdminCache = val;
      return val;
    } catch (_) {
      _isAdminCache = false;
      return false;
    }
  }

  static Future<bool> isUserBanned(String userId) async {
    if (userId.isEmpty) return false;
    try {
      final prof = await getProfileByUserId(userId);
      final raw = prof?.data['isBanned'];
      if (raw is bool) return raw;
      if (raw is String) {
        final lower = raw.toLowerCase();
        return lower == 'true' || lower == '1' || lower == 'yes';
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isCurrentUserBanned() async {
    if (_isBannedCache != null) return _isBannedCache!;
    final user = await getCurrentUser();
    if (user == null) {
      _isBannedCache = false;
      return false;
    }
    final banned = await isUserBanned(user.$id);
    _isBannedCache = banned;
    return banned;
  }

  // Admin helpers
  static Future<models.RowList> listProfiles({
    int limit = 50,
    String? cursor,
  }) async {
    final queries = <String>[
      Query.orderAsc('displayName'),
      Query.limit(limit),
      if (cursor != null) Query.cursorAfter(cursor),
    ];
    return _tables.listRows(
      databaseId: databaseId,
      tableId: profilesCollectionId,
      queries: queries,
    );
  }

  static Future<void> setAdminFlag(String userId, bool isAdmin) async {
    await _tables.updateRow(
      databaseId: databaseId,
      tableId: profilesCollectionId,
      rowId: userId,
      data: {'isAdmin': isAdmin},
    );
    if (_isAdminCache != null) {
      // If we toggled ourselves, reset cache.
      final me = await getCurrentUser();
      if (me != null && me.$id == userId) {
        _resetAuthCaches();
      }
    }
  }

  // Generic docs (TablesDB)
  static Future<models.Row> createDocument(
    String tableId,
    Map<String, dynamic> data, {
    List<String>? permissions,
  }) async {
    final me = await getCurrentUser();
    permissions ??= me != null
        ? [Permission.read(Role.any()), Permission.write(Role.user(me.$id))]
        : [Permission.read(Role.any())];
    return _tables.createRow(
      databaseId: databaseId,
      tableId: tableId,
      rowId: ID.unique(),
      data: data,
      permissions: permissions,
    );
  }

  static Future<models.RowList> getDocuments(
    String tableId, {
    List<String>? queries,
  }) => _tables.listRows(
    databaseId: databaseId,
    tableId: tableId,
    queries: queries ?? <String>[],
  );

  static Future<models.Row> createPost(Map<String, dynamic> data) async {
    // Posts table has a required `postId` column; keep it in sync with the row ID.
    final rowId = ID.unique();
    return _tables.createRow(
      databaseId: databaseId,
      tableId: postsCollectionId,
      rowId: rowId,
      data: <String, dynamic>{...data, 'postId': data['postId'] ?? rowId},
    );
  }

  // Posts
  static Future<models.RowList> fetchPosts({
    int limit = 20,
    String? cursorId,
  }) async {
    return await _tables.listRows(
      databaseId: databaseId,
      tableId: postsCollectionId,
      queries: <String>[
        Query.orderDesc('createdAt'),
        Query.limit(limit),
        if (cursorId != null) Query.cursorAfter(cursorId),
      ],
    );
  }

  static Future<List<String>> getFollowingUserIds(String userId) async {
    try {
      final res = await _tables.listRows(
        databaseId: databaseId,
        tableId: followsCollectionId,
        queries: [Query.equal('followerId', userId), Query.limit(500)],
      );
      return res.rows
          .map((d) => (d.data['followeeId'] as String))
          .toList(growable: false);
    } catch (_) {
      return <String>[];
    }
  }

  static Future<int> getFollowerCount(String userId) async {
    try {
      final res = await _tables.listRows(
        databaseId: databaseId,
        tableId: followsCollectionId,
        queries: [Query.equal('followeeId', userId), Query.limit(1000)],
      );
      return res.total;
    } catch (_) {
      return 0;
    }
  }

  static Future<models.RowList> fetchPostsByUserIds(
    List<String> userIds, {
    int limit = 20,
    String? cursorId,
  }) async {
    if (userIds.isEmpty) return models.RowList(total: 0, rows: []);
    return await _tables.listRows(
      databaseId: databaseId,
      tableId: postsCollectionId,
      queries: <String>[
        Query.equal('userId', userIds),
        Query.orderDesc('createdAt'),
        Query.limit(limit),
        if (cursorId != null) Query.cursorAfter(cursorId),
      ],
    );
  }

  static Future<models.RowList> fetchRepostsByUserIds(
    List<String> userIds, {
    int limit = 20,
  }) async {
    if (userIds.isEmpty) return models.RowList(total: 0, rows: []);
    return await _tables.listRows(
      databaseId: databaseId,
      tableId: repostsCollectionId,
      queries: <String>[
        Query.equal('userId', userIds),
        Query.orderDesc('createdAt'),
        Query.limit(limit),
      ],
    );
  }

  static Future<models.Row?> getProfileByUsername(String username) async {
    try {
      final res = await _tables.listRows(
        databaseId: databaseId,
        tableId: profilesCollectionId,
        queries: <String>[Query.equal('username', username), Query.limit(1)],
      );
      if (res.rows.isEmpty) return null;
      return res.rows.first;
    } catch (_) {
      return null;
    }
  }

  static Future<models.RowList> searchProfiles(
    String query, {
    int limit = 20,
  }) async {
    return await _tables.listRows(
      databaseId: databaseId,
      tableId: profilesCollectionId,
      queries: <String>[
        Query.search('username', query),
        Query.limit(limit),
      ],
    );
  }

  static Future<models.RowList> searchPostsByHashtag(
    String tag, {
    int limit = 20,
    String? cursorId,
  }) async {
    final query = '#$tag';
    return await _tables.listRows(
      databaseId: databaseId,
      tableId: postsCollectionId,
      queries: <String>[
        Query.search('content', query),
        Query.orderDesc('createdAt'),
        Query.limit(limit),
        if (cursorId != null) Query.cursorAfter(cursorId),
      ],
    );
  }

  static Future<void> updatePostSeo(
    String postId, {
    String? seoTitle,
    String? seoDescription,
    String? seoSlug,
    List<String>? seoKeywords,
  }) async {
    final data = <String, dynamic>{};
    if (seoTitle != null && seoTitle.isNotEmpty) {
      data['seoTitle'] = seoTitle;
    }
    if (seoDescription != null && seoDescription.isNotEmpty) {
      data['seoDescription'] = seoDescription;
    }
    if (seoSlug != null && seoSlug.isNotEmpty) {
      data['seoSlug'] = seoSlug;
    }
    if (seoKeywords != null && seoKeywords.isNotEmpty) {
      data['seoKeywords'] = seoKeywords;
    }
    if (data.isEmpty) return;
    await updateRow(postsCollectionId, postId, data);
  }

  static Future<models.RowList> searchPostsByText(
    String text, {
    int limit = 20,
    String? cursorId,
  }) async {
    return await _tables.listRows(
      databaseId: databaseId,
      tableId: postsCollectionId,
      queries: <String>[
        Query.search('content', text),
        Query.orderDesc('createdAt'),
        Query.limit(limit),
        if (cursorId != null) Query.cursorAfter(cursorId),
      ],
    );
  }

  static Future<void> incrementPostLikes(String postId, int delta) async {
    await _incrementPostField(postId, 'likes', delta);
  }

  static Future<void> incrementPostReposts(String postId, int delta) async {
    await _incrementPostField(postId, 'reposts', delta);
  }

  static Future<void> incrementPostComments(String postId, int delta) async {
    await _incrementPostField(postId, 'comments', delta);
  }

  static Future<void> incrementPostShares(String postId, int delta) async {
    await _incrementPostField(postId, 'shares', delta);
  }

  static Future<void> incrementPostImpressions(String postId, int delta) async {
    await _incrementPostField(postId, 'impressions', delta);
  }

  static Future<void> _incrementPostField(
    String postId,
    String field,
    int delta,
  ) async {
    try {
      final row = await getRow(postsCollectionId, postId);
      final current = row.data[field] ?? 0;
      final parsed = current is int ? current : int.tryParse('$current') ?? 0;
      final next = (parsed + delta).clamp(0, 1 << 31);
      await updateRow(postsCollectionId, postId, {field: next});
      if (field == 'impressions') {
        final boostId = row.data['activeBoostId'] as String?;
        final isBoosted = row.data['isBoosted'] as bool? ?? false;
        if (boostId != null && boostId.isNotEmpty && isBoosted) {
          try {
            final boostRow = await getRow(postBoostsCollectionId, boostId);
            final data = boostRow.data;
            final status = (data['status'] as String?)?.toLowerCase();
            if (status == 'running') {
              final deliveredRaw = data['deliveredImpressions'] ?? 0;
              final delivered = deliveredRaw is int
                  ? deliveredRaw
                  : int.tryParse('$deliveredRaw') ?? 0;
              final targetRaw = data['targetReach'] ?? 0;
              final target = targetRaw is int
                  ? targetRaw
                  : int.tryParse('$targetRaw') ?? 0;
              final newDelivered = (delivered + delta).clamp(
                0,
                target > 0 ? target : 1 << 31,
              );
              final updateData = <String, dynamic>{
                'deliveredImpressions': newDelivered,
              };
              if (target > 0 && newDelivered >= target) {
                updateData['status'] = 'completed';
                await updateRow(postsCollectionId, postId, {
                  'isBoosted': false,
                  'activeBoostId': null,
                });
              }
              await updateRow(postBoostsCollectionId, boostId, updateData);
            }
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  // Reposts (per-user tracking)
  static Future<bool> isPostRepostedBy(String userId, String postId) async {
    try {
      final res = await _tables.listRows(
        databaseId: databaseId,
        tableId: repostsCollectionId,
        queries: [
          Query.equal('userId', userId),
          Query.equal('postId', postId),
          Query.limit(1),
        ],
      );
      return res.rows.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<void> repostPost(String originalPostId) async {
    final user = await getCurrentUser();
    if (user == null) {
      throw StateError('User must be signed in to repost.');
    }

    // Toggle per-user repost record (mirror behavior, not a fresh post).
    try {
      final res = await _tables.listRows(
        databaseId: databaseId,
        tableId: repostsCollectionId,
        queries: [
          Query.equal('userId', user.$id),
          Query.equal('postId', originalPostId),
          Query.limit(1),
        ],
      );

      if (res.rows.isNotEmpty) {
        // Undo repost: remove record and decrement counter.
        for (final row in res.rows) {
          await _tables.deleteRow(
            databaseId: databaseId,
            tableId: repostsCollectionId,
            rowId: row.$id,
          );
        }
        await incrementPostReposts(originalPostId, -1);
      } else {
        // Create repost record and increment counter.
        await _tables.createRow(
          databaseId: databaseId,
          tableId: repostsCollectionId,
          rowId: ID.unique(),
          data: {
            'postId': originalPostId,
            'userId': user.$id,
            'createdAt': DateTime.now().toIso8601String(),
          },
        );
        await incrementPostReposts(originalPostId, 1);
      }
    } catch (_) {}
  }

  // Comments
  static Future<models.RowList> fetchComments(
    String postId, {
    int limit = 50,
  }) async {
    return await _tables.listRows(
      databaseId: databaseId,
      tableId: commentsCollectionId,
      queries: <String>[
        Query.equal('postId', postId),
        Query.orderDesc('createdAt'),
        Query.limit(limit),
      ],
    );
  }

  static Future<models.Row> createComment(String postId, String content) async {
    final user = await getCurrentUser();
    if (user == null) throw StateError('User must be signed in to comment.');
    final profile = await getProfileByUserId(user.$id);
    final username =
        (profile?.data['displayName'] as String?) ??
        (profile?.data['username'] as String?) ??
        user.name;
    final avatar = profile?.data['avatarUrl'] as String?;
    return _tables.createRow(
      databaseId: databaseId,
      tableId: commentsCollectionId,
      rowId: ID.unique(),
      data: {
        'type': 'text',
        'postId': postId,
        'userId': user.$id,
        'username': username,
        'userAvatar': avatar ?? '',
        'content': content,
        'likes': 0,
        'replies': 0,
        'createdAt': DateTime.now().toIso8601String(),
      },
    );
  }

  static Future<models.Row> createReplyComment(
    String postId,
    String parentCommentId,
    String content,
  ) async {
    final user = await getCurrentUser();
    if (user == null) throw StateError('User must be signed in to comment.');
    final profile = await getProfileByUserId(user.$id);
    final username =
        (profile?.data['displayName'] as String?) ??
        (profile?.data['username'] as String?) ??
        user.name;
    final avatar = profile?.data['avatarUrl'] as String?;
    return _tables.createRow(
      databaseId: databaseId,
      tableId: commentsCollectionId,
      rowId: ID.unique(),
      data: {
        'type': 'text',
        'postId': postId,
        'parentCommentId': parentCommentId,
        'userId': user.$id,
        'username': username,
        'userAvatar': avatar ?? '',
        'content': content,
        'likes': 0,
        'replies': 0,
        'createdAt': DateTime.now().toIso8601String(),
      },
    );
  }

  static Future<models.Row> createVoiceComment(
    String postId,
    String voiceUrl,
  ) async {
    final user = await getCurrentUser();
    if (user == null) throw StateError('User must be signed in to comment.');
    final profile = await getProfileByUserId(user.$id);
    final username =
        (profile?.data['displayName'] as String?) ??
        (profile?.data['username'] as String?) ??
        user.name;
    final avatar = profile?.data['avatarUrl'] as String?;
    return _tables.createRow(
      databaseId: databaseId,
      tableId: commentsCollectionId,
      rowId: ID.unique(),
      data: {
        'type': 'voice',
        'postId': postId,
        'userId': user.$id,
        'username': username,
        'userAvatar': avatar ?? '',
        'voiceUrl': voiceUrl,
        'likes': 0,
        'replies': 0,
        'createdAt': DateTime.now().toIso8601String(),
      },
    );
  }

  // Likes
  static Future<bool> isPostLikedBy(String userId, String postId) async {
    try {
      final res = await _tables.listRows(
        databaseId: databaseId,
        tableId: likesCollectionId,
        queries: [
          Query.equal('userId', userId),
          Query.equal('postId', postId),
          Query.limit(1),
        ],
      );
      return res.rows.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<models.Row> likePost(String postId) async {
    final user = await getCurrentUser();
    if (user == null) throw StateError('User must be signed in to like posts.');
    final doc = await _tables.createRow(
      databaseId: databaseId,
      tableId: likesCollectionId,
      rowId: ID.unique(),
      data: {
        'postId': postId,
        'userId': user.$id,
        'createdAt': DateTime.now().toIso8601String(),
      },
    );
    await incrementPostLikes(postId, 1);
    return doc;
  }

  static Future<void> unlikePost(String postId) async {
    final user = await getCurrentUser();
    if (user == null) return;
    try {
      final res = await _tables.listRows(
        databaseId: databaseId,
        tableId: likesCollectionId,
        queries: [
          Query.equal('userId', user.$id),
          Query.equal('postId', postId),
        ],
      );
      for (final row in res.rows) {
        await _tables.deleteRow(
          databaseId: databaseId,
          tableId: likesCollectionId,
          rowId: row.$id,
        );
      }
      await incrementPostLikes(postId, -1);
    } catch (_) {}
  }

  // Saves
  static Future<bool> isPostSavedBy(String userId, String postId) async {
    try {
      final res = await _tables.listRows(
        databaseId: databaseId,
        tableId: savesCollectionId,
        queries: [
          Query.equal('userId', userId),
          Query.equal('postId', postId),
          Query.limit(1),
        ],
      );
      return res.rows.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<models.Row> savePost(String postId) async {
    final user = await getCurrentUser();
    if (user == null) throw StateError('User must be signed in to save posts.');
    return _tables.createRow(
      databaseId: databaseId,
      tableId: savesCollectionId,
      rowId: ID.unique(),
      data: {
        'postId': postId,
        'userId': user.$id,
        'createdAt': DateTime.now().toIso8601String(),
      },
    );
  }

  static Future<void> unsavePost(String postId) async {
    final user = await getCurrentUser();
    if (user == null) return;
    try {
      final res = await _tables.listRows(
        databaseId: databaseId,
        tableId: savesCollectionId,
        queries: [
          Query.equal('userId', user.$id),
          Query.equal('postId', postId),
        ],
      );
      for (final row in res.rows) {
        await _tables.deleteRow(
          databaseId: databaseId,
          tableId: savesCollectionId,
          rowId: row.$id,
        );
      }
    } catch (_) {}
  }

  // Follows
  static Future<bool> isFollowing(String followerId, String followeeId) async {
    try {
      final res = await _tables.listRows(
        databaseId: databaseId,
        tableId: followsCollectionId,
        queries: [
          Query.equal('followerId', followerId),
          Query.equal('followeeId', followeeId),
          Query.limit(1),
        ],
      );
      return res.rows.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<void> followUser(String followeeId) async {
    final user = await getCurrentUser();
    if (user == null) return;
    try {
      await _tables.createRow(
        databaseId: databaseId,
        tableId: followsCollectionId,
        rowId: ID.unique(),
        data: {
          'followerId': user.$id,
          'followeeId': followeeId,
          // Match follows table schema: required followedAt column.
          'followedAt': DateTime.now().toIso8601String(),
        },
      );
      followingVersion.value++;
    } catch (_) {}
  }

  static Future<void> unfollowUser(String followeeId) async {
    final user = await getCurrentUser();
    if (user == null) return;
    try {
      final res = await _tables.listRows(
        databaseId: databaseId,
        tableId: followsCollectionId,
        queries: [
          Query.equal('followerId', user.$id),
          Query.equal('followeeId', followeeId),
        ],
      );
      for (final row in res.rows) {
        await _tables.deleteRow(
          databaseId: databaseId,
          tableId: followsCollectionId,
          rowId: row.$id,
        );
      }
      followingVersion.value++;
    } catch (_) {}
  }

  // Reports
  static Future<models.Row> reportPost(String postId, String reason) async {
    final user = await getCurrentUser();
    if (user == null)
      throw StateError('User must be signed in to report posts.');
    return _tables.createRow(
      databaseId: databaseId,
      tableId: reportsCollectionId,
      rowId: ID.unique(),
      data: {
        'postId': postId,
        'userId': user.$id,
        'reason': reason,
        'createdAt': DateTime.now().toIso8601String(),
      },
    );
  }

  static Future<void> _incrementCommentField(
    String commentId,
    String field,
    int delta,
  ) async {
    try {
      final row = await _tables.getRow(
        databaseId: databaseId,
        tableId: commentsCollectionId,
        rowId: commentId,
      );
      final current = row.data[field] ?? 0;
      final parsed = current is int ? current : int.tryParse('$current') ?? 0;
      final next = (parsed + delta).clamp(0, 1 << 31);
      await _tables.updateRow(
        databaseId: databaseId,
        tableId: commentsCollectionId,
        rowId: commentId,
        data: {field: next},
      );
    } catch (_) {}
  }

  static Future<void> incrementCommentLikes(String commentId, int delta) =>
      _incrementCommentField(commentId, 'likes', delta);

  static Future<void> incrementCommentReplies(String commentId, int delta) =>
      _incrementCommentField(commentId, 'replies', delta);

  // Comment likes
  static Future<bool> isCommentLikedBy(String userId, String commentId) async {
    try {
      final res = await _tables.listRows(
        databaseId: databaseId,
        tableId: commentLikesCollectionId,
        queries: [
          Query.equal('userId', userId),
          Query.equal('commentId', commentId),
          Query.limit(1),
        ],
      );
      return res.rows.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<void> likeComment(String commentId) async {
    final user = await getCurrentUser();
    if (user == null)
      throw StateError('User must be signed in to like comments.');
    await _tables.createRow(
      databaseId: databaseId,
      tableId: commentLikesCollectionId,
      rowId: ID.unique(),
      data: {
        'commentId': commentId,
        'userId': user.$id,
        'createdAt': DateTime.now().toIso8601String(),
      },
    );
    await incrementCommentLikes(commentId, 1);
  }

  static Future<void> unlikeComment(String commentId) async {
    final user = await getCurrentUser();
    if (user == null) return;
    try {
      final res = await _tables.listRows(
        databaseId: databaseId,
        tableId: commentLikesCollectionId,
        queries: [
          Query.equal('userId', user.$id),
          Query.equal('commentId', commentId),
        ],
      );
      for (final row in res.rows) {
        await _tables.deleteRow(
          databaseId: databaseId,
          tableId: commentLikesCollectionId,
          rowId: row.$id,
        );
      }
      await incrementCommentLikes(commentId, -1);
    } catch (_) {}
  }

  static Future<void> deleteComment(String commentId) async {
    await _tables.deleteRow(
      databaseId: databaseId,
      tableId: commentsCollectionId,
      rowId: commentId,
    );
  }

  static Future<void> deletePost(String postId) async {
    await _tables.deleteRow(
      databaseId: databaseId,
      tableId: postsCollectionId,
      rowId: postId,
    );
  }

  static Future<void> logout() async {
    try {
      await _account.deleteSession(sessionId: 'current');
    } catch (_) {
      // ignore
    }
  }

  static Future<void> createStatus(
    String statusId,
    String userId,
    String mediaPath,
    DateTime timestamp, {
    String caption = '',
  }) async {
    try {
      await _tables.createRow(
        databaseId: databaseId,
        tableId: statusesCollectionId,
        rowId: statusId,
        data: {
          'timestamp': timestamp.toUtc().toIso8601String(),
          if (caption.isNotEmpty) 'caption': caption,
          'userId': userId,
          'statusId': statusId,
          'mediaPath': mediaPath,
        },
      );
    } catch (_) {}
  }

  static Future<List<StatusUpdate>> fetchStatuses({int limit = 40}) async {
    try {
      final res = await _tables.listRows(
        databaseId: databaseId,
        tableId: statusesCollectionId,
        queries: <String>[Query.orderDesc('timestamp'), Query.limit(limit)],
      );
      final List<StatusUpdate> items = [];
      final Map<String, models.Row?> profileCache = {};
      for (final row in res.rows) {
        final data = row.data;
        final timestampStr = data['timestamp'] as String?;
        final timestamp =
            DateTime.tryParse(timestampStr ?? '') ?? DateTime.now();
        final userId = data['userId'] as String? ?? '';
        String username = 'User';
        String userAvatar = '';
        String? mediaPath = data['mediaPath'] as String?;
        if (userId.isNotEmpty) {
          models.Row? profile;
          if (profileCache.containsKey(userId)) {
            profile = profileCache[userId];
          } else {
            profile = await getProfileByUserId(userId);
            profileCache[userId] = profile;
          }
          if (profile != null) {
            final profileData = profile.data;
            username =
                (profileData['displayName'] as String?)?.trim() ??
                (profileData['username'] as String?)?.trim() ??
                username;
            final rawAvatar = (profileData['avatarUrl'] as String?)?.trim();
            if (rawAvatar != null && rawAvatar.isNotEmpty) {
              userAvatar = rawAvatar.startsWith('http')
                  ? rawAvatar
                  : await WasabiService.getSignedUrl(rawAvatar);
            }
          }
        }
        final List<String> mediaUrls = [];
        if (mediaPath != null && mediaPath.isNotEmpty) {
          try {
            final signed = await WasabiService.getSignedUrl(mediaPath);
            mediaUrls.add(signed);
          } catch (_) {}
        }
        items.add(
          StatusUpdate(
            id: row.$id,
            username: username,
            userAvatar: userAvatar,
            timestamp: timestamp,
            isViewed: false,
            mediaCount: mediaUrls.length,
            mediaUrls: mediaUrls,
            caption: data['caption'] as String? ?? '',
          ),
        );
      }
      return items;
    } catch (_) {
      return [];
    }
  }

  static Future<List<AppNotification>> fetchNotifications(
    String userId, {
    int limit = 20,
  }) async {
    try {
      final res = await _tables.listRows(
        databaseId: databaseId,
        tableId: notificationsCollectionId,
        queries: <String>[
          Query.equal('userId', userId),
          Query.orderDesc('timestamp'),
          Query.limit(limit),
        ],
      );
      final List<AppNotification> items = [];
      for (final row in res.rows) {
        final data = row.data;
        final timestampStr = data['timestamp'] as String?;
        final timestamp =
            DateTime.tryParse(timestampStr ?? '') ?? DateTime.now();
        items.add(
          AppNotification(
            id: row.$id,
            title: data['title'] as String? ?? 'Notification',
            body: data['body'] as String? ?? '',
            timestamp: timestamp,
            actorName: data['actorName'] as String?,
            actorAvatar: data['actorAvatar'] as String?,
            type: data['type'] as String?,
          ),
        );
      }
      return items;
    } catch (_) {
      return [];
    }
  }

  static Future<void> cleanupExpiredStatuses() async {
    try {
      final cutoff = DateTime.now()
          .subtract(const Duration(hours: 24))
          .toUtc()
          .toIso8601String();
      while (true) {
        final res = await _tables.listRows(
          databaseId: databaseId,
          tableId: statusesCollectionId,
          queries: <String>[
            Query.lessThan('timestamp', cutoff),
            Query.limit(100),
          ],
        );
        if (res.rows.isEmpty) break;
        for (final row in res.rows) {
          final data = row.data;
          final mediaPath = data['mediaPath'] as String?;
          if (mediaPath != null && mediaPath.isNotEmpty) {
            try {
              await WasabiService.deleteFile(mediaPath);
            } catch (_) {}
          }
          await _tables.deleteRow(
            databaseId: databaseId,
            tableId: statusesCollectionId,
            rowId: row.$id,
          );
        }
        if (res.rows.length < 100) break;
      }
    } catch (_) {}
  }

  // Profiles
  static Future<models.Row?> getProfileByUserId(String userId) async {
    try {
      final res = await _tables.listRows(
        databaseId: databaseId,
        tableId: profilesCollectionId,
        // Profiles table uses camelCase `userId`.
        queries: [Query.equal('userId', userId), Query.limit(1)],
      );
      return res.rows.isNotEmpty ? res.rows.first : null;
    } catch (_) {
      return null;
    }
  }

  static Future<models.Row?> getUserMetaByUserId(String userId) async {
    try {
      final res = await _tables.listRows(
        databaseId: databaseId,
        tableId: usersCollectionId,
        queries: <String>[Query.equal('userId', userId), Query.limit(1)],
      );
      return res.rows.isNotEmpty ? res.rows.first : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> updateUserProfile(
    String userId,
    Map<String, dynamic> data,
  ) async {
    // Ensure required username/displayName are always present.
    final userMeta = await getUserMetaByUserId(userId);
    final existing = await getProfileByUserId(userId);
    final existingData = existing?.data ?? <String, dynamic>{};
    final metaData = userMeta?.data ?? <String, dynamic>{};

    final String username =
        (data['username'] as String?) ??
        (existingData['username'] as String?) ??
        (metaData['username'] as String?) ??
        '';

    final String displayName =
        (data['displayName'] as String?) ??
        (existingData['displayName'] as String?) ??
        (metaData['username'] as String?) ??
        username;

    final payload = <String, dynamic>{
      ...data,
      'userId': userId,
      'username': username,
      'displayName': displayName,
    };
    try {
      await updateRow(profilesCollectionId, userId, payload);
    } on AppwriteException catch (e) {
      if (e.code == 404) {
        await _tables.createRow(
          databaseId: databaseId,
          tableId: profilesCollectionId,
          rowId: userId,
          data: payload,
        );
      } else {
        rethrow;
      }
    }
  }

  // Chats & messages
  static Future<models.RowList> fetchChatsForUser(String userId) async {
    try {
      final res = await _tables.listRows(
        databaseId: databaseId,
        tableId: chatsCollectionId,
        queries: <String>[
          // memberIds is stored as a comma-separated string.
          Query.search('memberIds', userId),
        ],
      );
      if (res.total > 0) return res;
    } catch (_) {
      // fall through to broad fetch
    }
    // Fallback: fetch a reasonable page and filter client-side.
    final res = await _tables.listRows(
      databaseId: databaseId,
      tableId: chatsCollectionId,
      queries: <String>[Query.limit(100)],
    );
    final filtered = res.rows
        .where((row) {
          final raw = (row.data['memberIds'] as String?) ?? '';
          return raw.split(',').map((e) => e.trim()).contains(userId);
        })
        .toList(growable: false);
    return models.RowList(total: filtered.length, rows: filtered);
  }

  static Future<models.RowList> fetchMessagesForChat(
    String chatId, {
    int limit = 100,
  }) async {
    return await _tables.listRows(
      databaseId: databaseId,
      tableId: messagesCollectionId,
      queries: <String>[
        Query.equal('chatId', chatId),
        Query.orderDesc('timestamp'),
        Query.limit(limit),
      ],
    );
  }

  // News (separate table for human- and AI-authored articles)
  static Future<models.Row> createNewsArticle(Map<String, dynamic> data) async {
    final rowId = ID.unique();
    return _tables.createRow(
      databaseId: databaseId,
      tableId: newsCollectionId,
      rowId: rowId,
      data: <String, dynamic>{...data, 'newsId': data['newsId'] ?? rowId},
    );
  }

  static Future<models.RowList> fetchNewsArticles({
    int limit = 20,
    String? cursorId,
  }) async {
    return _tables.listRows(
      databaseId: databaseId,
      tableId: newsCollectionId,
      queries: <String>[
        Query.orderDesc('createdAt'),
        Query.limit(limit),
        if (cursorId != null) Query.cursorAfter(cursorId),
      ],
    );
  }
}
