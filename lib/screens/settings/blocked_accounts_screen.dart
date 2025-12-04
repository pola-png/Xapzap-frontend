import 'package:flutter/material.dart';

class BlockedAccountsScreen extends StatelessWidget {
  const BlockedAccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Blocked Accounts'),
      ),
      body: const Center(
        child: Text('Blocked Accounts Screen'),
      ),
    );
  }
}
