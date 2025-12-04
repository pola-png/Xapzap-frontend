import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../../providers/theme_provider.dart';

class AppearanceSettingsScreen extends StatefulWidget {
  const AppearanceSettingsScreen({super.key});

  @override
  State<AppearanceSettingsScreen> createState() => _AppearanceSettingsScreenState();
}

class _AppearanceSettingsScreenState extends State<AppearanceSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _buildThemeOptions(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 56,
      padding: const EdgeInsets.fromLTRB(16, 44, 16, 0),
      decoration: BoxDecoration(
        color: Theme.of(context).appBarTheme.backgroundColor,
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor, width: 1)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Icon(LucideIcons.arrowLeft, size: 20, color: Theme.of(context).appBarTheme.foregroundColor),
          ),
          const SizedBox(width: 16),
          Text(
            'Appearance',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).appBarTheme.foregroundColor),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeOptions() {
    final themeProvider = Provider.of<ThemeProvider>(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Theme',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),
        _buildThemeOption(
          themeProvider,
          ThemeMode.light,
          'Light',
          'Clean and bright interface',
          LucideIcons.sun,
        ),
        const SizedBox(height: 12),
        _buildThemeOption(
          themeProvider,
          ThemeMode.dark,
          'Dark',
          'Easy on the eyes in low light',
          LucideIcons.moon,
        ),
        const SizedBox(height: 12),
        _buildThemeOption(
          themeProvider,
          ThemeMode.system,
          'System',
          'Match system setting',
          LucideIcons.smartphone,
        ),
      ],
    );
  }

  Widget _buildThemeOption(ThemeProvider themeProvider, ThemeMode mode, String title, String description, IconData icon) {
    final isSelected = themeProvider.themeMode == mode;

    return GestureDetector(
      onTap: () => themeProvider.setThemeMode(mode),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? const Color(0xFF29ABE2) : Theme.of(context).dividerColor,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
          color: isSelected ? const Color(0xFF29ABE2).withOpacity(0.05) : Theme.of(context).cardColor,
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF29ABE2) : Theme.of(context).dividerColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                color: isSelected ? Colors.white : Theme.of(context).iconTheme.color,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? const Color(0xFF29ABE2) : Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(
                LucideIcons.checkCircle,
                color: Color(0xFF29ABE2),
                size: 24,
              ),
          ],
        ),
      ),
    );
  }
}
