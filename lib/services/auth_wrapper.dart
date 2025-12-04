import 'package:flutter/material.dart';
import '../screens/main_screen.dart';
import '../screens/auth/sign_in_screen.dart';
import '../screens/banned_screen.dart';
import 'appwrite_service.dart';

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _isLoading = true;
  bool _isAuthenticated = false;
  bool _isBanned = false;

  @override
  void initState() {
    super.initState();
    _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    try {
      final user = await AppwriteService.getCurrentUser();
      var banned = false;
      if (user != null) {
        banned = await AppwriteService.isUserBanned(user.$id);
      }
      setState(() {
        _isAuthenticated = user != null && !banned;
        _isBanned = banned;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isAuthenticated = false;
        _isBanned = false;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            color: Color(0xFF29ABE2),
          ),
        ),
      );
    }

    if (_isBanned) {
      return const BannedScreen();
    }

    return _isAuthenticated ? const MainScreen() : const SignInScreen();
  }
}
