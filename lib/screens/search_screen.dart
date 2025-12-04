import 'package:flutter/material.dart';
import 'hashtag_feed_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];

  final List<Map<String, dynamic>> _users = [
    {'name': 'John Doe', 'handle': '@john', 'avatar': ''},
    {'name': 'Jane Smith', 'handle': '@jane', 'avatar': ''},
  ];

  final List<Map<String, dynamic>> _posts = [
    {'author': 'John Doe', 'content': 'Just setting up my XapZap!'},
    {'author': 'Jane Smith', 'content': 'Loving this new app!'},
  ];

  void _performSearch(String query) {
    if (query.isEmpty) {
      setState(() => _searchResults = []);
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

    final lowerCaseQuery = query.toLowerCase();
    final userResults = _users
        .where((user) =>
            user['name']!.toLowerCase().contains(lowerCaseQuery) ||
            user['handle']!.toLowerCase().contains(lowerCaseQuery))
        .map((user) => {'type': 'user', ...user});

    final postResults = _posts
        .where((post) => post['content']!.toLowerCase().contains(lowerCaseQuery))
        .map((post) => {'type': 'post', ...post});

    setState(() {
      _searchResults = [...userResults, ...postResults];
    });
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
