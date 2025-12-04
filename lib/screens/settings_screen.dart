import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'settings/account_settings_screen.dart';
import 'settings/privacy_settings_screen.dart';
import 'settings/appearance_settings_screen.dart';
import 'settings/notifications_settings_screen.dart';
import 'settings/help_settings_screen.dart';
import '../services/appwrite_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: _buildSettingsMenu(context),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      height: 56, // h-14
      padding: const EdgeInsets.fromLTRB(16, 44, 16, 0),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB), width: 1)),
      ),
      child: Row(
        children: [
          // Back Button
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                LucideIcons.arrowLeft,
                size: 20,
                color: Colors.black,
              ),
            ),
          ),
          const SizedBox(width: 16),
          const Text(
            'Settings',
            style: TextStyle(
              fontSize: 20, // text-xl
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsMenu(BuildContext context) {
    return Column(
      children: [
        _buildMenuItem(
          context,
          icon: LucideIcons.user,
          title: 'Account Information',
          description: 'Manage your name, email, and personal details',
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const AccountSettingsScreen()),
            );
          },
        ),
        _buildMenuItem(
          context,
          icon: LucideIcons.shield,
          title: 'Privacy & Security',
          description: 'Control who can see your activity and posts',
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const PrivacySettingsScreen()),
            );
          },
        ),
        _buildMenuItem(
          context,
          icon: LucideIcons.bell,
          title: 'Notifications',
          description: 'Manage your alert preferences and settings',
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const NotificationsSettingsScreen()),
            );
          },
        ),
        _buildMenuItem(
          context,
          icon: LucideIcons.paintbrush,
          title: 'Appearance',
          description: 'Customize app theme and display options',
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const AppearanceSettingsScreen()),
            );
          },
        ),
        _buildMenuItem(
          context,
          icon: LucideIcons.helpCircle,
          title: 'Help & Support',
          description: 'Access FAQs, contact support, and get help',
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const HelpSettingsScreen()),
            );
          },
        ),
        const Spacer(),
        _buildLogoutButton(context),
      ],
    );
  }

  Widget _buildMenuItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16), // p-4
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB), width: 1)),
        ),
        child: Row(
          children: [
            // Icon - h-6 w-6 (24px)
            Icon(
              icon,
              size: 24,
              color: const Color(0xFF6B7280), // text-muted-foreground
            ),
            const SizedBox(width: 16), // mr-4
            // Text Block
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500, // font-medium
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 14, // text-sm
                      color: Color(0xFF6B7280), // text-muted-foreground
                    ),
                  ),
                ],
              ),
            ),
            // Chevron Right
            const Icon(
              LucideIcons.chevronRight,
              size: 20,
              color: Color(0xFF9CA3AF),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogoutButton(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: SizedBox(
        width: double.infinity,
        child: GestureDetector(
          onTap: () => _showLogoutDialog(context),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE5E7EB)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  LucideIcons.logOut,
                  size: 20,
                  color: Color(0xFFEF4444), // text-red-500
                ),
                SizedBox(width: 8),
                Text(
                  'Logout',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFFEF4444), // text-red-500
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Logout'),
          content: const Text('Are you sure you want to logout?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Color(0xFF6B7280)),
              ),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context); // Close dialog
                await AppwriteService.signOut();
                if (context.mounted) {
                  Navigator.pushNamedAndRemoveUntil(context, '/signin', (route) => false);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Logged out successfully'),
                      backgroundColor: Color(0xFF10B981),
                    ),
                  );
                }
              },
              child: const Text(
                'Logout',
                style: TextStyle(color: Color(0xFFEF4444)),
              ),
            ),
          ],
        );
      },
    );
  }
}
