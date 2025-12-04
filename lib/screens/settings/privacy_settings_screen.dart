import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'blocked_accounts_screen.dart';
import 'change_password_screen.dart';

class PrivacySettingsScreen extends StatefulWidget {
  const PrivacySettingsScreen({super.key});

  @override
  State<PrivacySettingsScreen> createState() => _PrivacySettingsScreenState();
}

class _PrivacySettingsScreenState extends State<PrivacySettingsScreen> {
  bool _privateAccount = false;
  bool _showActivityStatus = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _buildSettings(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 56,
      padding: const EdgeInsets.fromLTRB(16, 44, 16, 0),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB), width: 1)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Icon(LucideIcons.arrowLeft, size: 20),
          ),
          const SizedBox(width: 16),
          const Text(
            'Privacy & Security',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildSettings() {
    return ListView(
      children: [
        _buildSwitchOption(
          'Private Account',
          'Only approved followers can see your posts',
          _privateAccount,
          (value) => setState(() => _privateAccount = value),
        ),
        _buildSwitchOption(
          'Show Activity Status',
          'Let others see when you\'re online',
          _showActivityStatus,
          (value) => setState(() => _showActivityStatus = value),
        ),
        _buildNavigationOption(
          'Blocked Accounts',
          'Manage users you\'ve blocked',
          LucideIcons.ban,
          () {
            Navigator.push(context, MaterialPageRoute(builder: (context) => const BlockedAccountsScreen()));
          },
        ),
        _buildNavigationOption(
          'Change Password',
          'Update your account password',
          LucideIcons.lock,
          () {
            Navigator.push(context, MaterialPageRoute(builder: (context) => const ChangePasswordScreen()));
          },
        ),
      ],
    );
  }

  Widget _buildSwitchOption(String title, String description, bool value, Function(bool) onChanged) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB), width: 1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: const Color(0xFF29ABE2),
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationOption(String title, String description, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB), width: 1)),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 24,
              color: const Color(0xFF6B7280),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),
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
}