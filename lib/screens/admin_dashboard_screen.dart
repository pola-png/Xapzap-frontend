import 'package:flutter/material.dart';
import 'package:appwrite/models.dart' as aw;
import '../services/appwrite_service.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  bool _loading = true;
  bool _isAdmin = false;
  List<aw.Row> _profiles = [];
  String? _cursor;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final isAdmin = await AppwriteService.isCurrentUserAdmin();
    if (!mounted) return;
    setState(() {
      _isAdmin = isAdmin;
    });
    if (isAdmin) {
      await _loadProfiles(reset: true);
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadProfiles({bool reset = false}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _profiles = [];
        _cursor = null;
      });
    }
    try {
      final res = await AppwriteService.listProfiles(limit: 50, cursor: _cursor);
      if (!mounted) return;
      setState(() {
        _profiles.addAll(res.rows);
        if (res.rows.isNotEmpty) {
          _cursor = res.rows.last.$id;
        } else {
          _cursor = null;
        }
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleAdmin(aw.Row row, bool value) async {
    final userId = row.$id;
    setState(() {
      final idx = _profiles.indexWhere((p) => p.$id == userId);
      if (idx != -1) {
        _profiles[idx].data['isAdmin'] = value;
      }
    });
    try {
      await AppwriteService.setAdminFlag(userId, value);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Admin ${value ? "granted" : "revoked"} for ${row.data['displayName'] ?? row.data['username'] ?? userId}')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to update admin: $e')));
      }
      setState(() {
        final idx = _profiles.indexWhere((p) => p.$id == userId);
        if (idx != -1) {
          _profiles[idx].data['isAdmin'] = !value;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!_isAdmin) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Admin Dashboard'),
          backgroundColor: theme.colorScheme.surface,
        ),
        body: const Center(
          child: Text('Admins only'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        backgroundColor: theme.colorScheme.surface,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadProfiles(reset: true),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadProfiles(reset: true),
        child: _loading && _profiles.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : ListView.builder(
                itemCount: _profiles.length,
                itemBuilder: (context, index) {
                  final row = _profiles[index];
                  final data = row.data;
                  final name = (data['displayName'] as String?) ??
                      (data['username'] as String?) ??
                      row.$id;
                  final isAdmin = (data['isAdmin'] is bool && data['isAdmin'] == true) ||
                      (data['isAdmin'] is String &&
                          (data['isAdmin'] as String).toLowerCase() == 'true');
                  return SwitchListTile(
                    title: Text(name),
                    subtitle: Text(data['username'] as String? ?? ''),
                    value: isAdmin,
                    onChanged: (val) => _toggleAdmin(row, val),
                  );
                },
              ),
      ),
    );
  }
}
