import 'package:flutter/material.dart';
import 'package:appwrite/models.dart' as aw;

import '../services/appwrite_service.dart';
import 'hashtag_feed_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isLoading = false;
  String? _error;

  Future<void> _performSearch(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _error = null;
        _isLoading = false;
      });
      return;
    }

    // Hashtag search: open dedicated hashtag feed.
    if (query.startsWith('#') && query.length > 1) {
      final tag = query.substring(1);
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => HashtagFeedScreen(tag: tag),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final List<Map<String, dynamic>> results = [];

      // User search: by username (handle), stripping leading '@' if present.
      final raw = query.trim();
      final handle = raw.startsWith('@') ? raw.substring(1) : raw;
      if (handle.isNotEmpty) {
        final aw.RowList profiles =
            await AppwriteService.searchProfiles(handle, limit: 20);
        for (final p in profiles.rows) {
          final data = p.data;
          final username = (data['username'] as String?) ?? '';
          final displayName =
              (data['displayName'] as String?) ?? (username.isNotEmpty ? username : 'User');
          final avatar = (data['avatarUrl'] as String?) ?? '';

          results.add({
            'type': 'user',
            'id': p.$id,
            'name': displayName,
            'handle': username.isNotEmpty ? '@$username' : '',
            'avatar': avatar,
          });
        }
      }

      // Post search: search text in post content.
      final aw.RowList posts =
          await AppwriteService.searchPostsByText(query, limit: 40);
      for (final row in posts.rows) {
        final data = row.data;
        results.add({
          'type': 'post',
          'id': row.$id,
          'author': (data['username'] as String?) ?? 'Unknown',
          'content': (data['content'] as String?) ?? '',
        });
      }

      setState(() {
        _searchResults = results;
        _isLoading = false;
      });
    } catch (_) {
      setState(() {
        _isLoading = false;
        _error = 'Failed to search. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search XapZap...',
            border: InputBorder.none,
          ),
          onChanged: _performSearch,
        ),
      ),
      body: _searchController.text.isEmpty
          ? const Center(
              child: Text('Search for users and posts.'),
            )
          : _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text(_error!))
                  : _searchResults.isEmpty
                      ? const Center(
                          child: Text('No results found.'),
                        )
                      : ListView.builder(
                          itemCount: _searchResults.length,
                          itemBuilder: (context, index) {
                            final result = _searchResults[index];
                            if (result['type'] == 'user') {
                              return _buildUserResult(result);
                            } else {
                              return _buildPostResult(result);
                            }
                          },
                        ),
    );
  }

  Widget _buildUserResult(Map<String, dynamic> user) {
    return ListTile(
      leading: CircleAvatar(
        radius: 30,
        child: Text(user['name']![0]),
      ),
      title: Text(user['name']!),
      subtitle: Text(user['handle']!),
      onTap: () {
        // TODO: Navigate to user profile
      },
    );
  }

  Widget _buildPostResult(Map<String, dynamic> post) {
    return ListTile(
      leading: const Icon(Icons.article),
      title: Text(post['content']!),
      subtitle: Text('Post by ${post['author']}'),
      onTap: () {
        // TODO: Navigate to post
      },
    );
  }
}
