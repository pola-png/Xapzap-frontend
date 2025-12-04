import 'package:flutter/material.dart';

class BannedScreen extends StatelessWidget {
  const BannedScreen({super.key});

  void _showSupportDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Contact Support'),
        content: const Text(
          'If you believe this ban is a mistake or you want to appeal it, '
          'please contact our support team at:\n\n'
          'support@xapzap.com\n\n'
          'Include your username and a short explanation. We’ll review your case as soon as possible.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.block,
                      size: 64,
                      color: Colors.redAccent,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Account Restricted',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Your XapZap account has been banned for violating our community guidelines. '
                      'You can no longer use the app with this account.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'If you think this is a mistake, you can contact support or submit an appeal.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 44,
                      child: ElevatedButton(
                        onPressed: () => _showSupportDialog(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1DA1F2),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text('Contact Support'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 44,
                      child: OutlinedButton(
                        onPressed: () => _showSupportDialog(context),
                        child: const Text('Appeal Ban'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

