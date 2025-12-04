import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../services/appwrite_service.dart';
import '../../services/auth_wrapper.dart';
import 'dart:html' as html;

enum AuthMode { signin, signup }

class AuthForm extends StatefulWidget {
  final AuthMode mode;

  const AuthForm({super.key, required this.mode});

  @override
  State<AuthForm> createState() => _AuthFormState();
}

class _AuthFormState extends State<AuthForm> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _usernameController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  Widget build(BuildContext context) {
    // On web, prompt to open/install the app for auth.
    if (kIsWeb) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                elevation: 6,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Continue in the XapZap app',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Auth is only available in the mobile app. Open XapZap to sign in or sign up.',
                        style: TextStyle(fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: ElevatedButton(
                          onPressed: _openApp,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1DA1F2),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: const Text('Open XapZap'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: OutlinedButton(
                          onPressed: _openStore,
                          child: const Text('Install the app'),
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

    final theme = Theme.of(context);
    final scaffoldColor = theme.scaffoldBackgroundColor;

    return Scaffold(
      backgroundColor: scaffoldColor,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 512),
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildHeader(),
                      const SizedBox(height: 32),
                      _buildInputFields(),
                      const SizedBox(height: 8),
                      _buildPrimaryButton(),
                      const SizedBox(height: 24),
                      _buildFooter(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          widget.mode == AuthMode.signin ? 'Welcome Back!' : 'Create an Account',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          widget.mode == AuthMode.signin
              ? 'Enter your credentials to access your account.'
              : 'Enter your details below to create your account.',
          style: TextStyle(
            fontSize: 14,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildInputFields() {
    return Column(
      children: [
        if (widget.mode == AuthMode.signup) ...[
          _buildUsernameField(),
          const SizedBox(height: 16),
        ],
        _buildEmailField(),
        const SizedBox(height: 16),
        _buildPasswordField(),
        if (widget.mode == AuthMode.signup) ...[
          const SizedBox(height: 16),
          _buildConfirmPasswordField(),
        ],
      ],
    );
  }

  Widget _buildUsernameField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Username', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        TextFormField(
          controller: _usernameController,
          decoration: InputDecoration(
            hintText: 'e.g., yourusername',
            prefixIcon: const Icon(Icons.alternate_email, size: 16, color: Color(0xFF9CA3AF)),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          validator: (value) {
            final v = value?.trim() ?? '';
            if (v.isEmpty) return 'Please enter a username';
            final handle = v.startsWith('@') ? v.substring(1) : v;
            if (handle.length < 3) return 'Username must be at least 3 characters';
            if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(handle)) {
              return 'Only letters, numbers, and _ allowed';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildEmailField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Email', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        TextFormField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            hintText: 'name@example.com',
            prefixIcon: const Icon(Icons.email_outlined, size: 16, color: Color(0xFF9CA3AF)),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          validator: (value) {
            if (value == null || !RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value)) {
              return 'Please enter a valid email';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildPasswordField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Password', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        TextFormField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          decoration: InputDecoration(
            hintText: 'Enter your password',
            prefixIcon: const Icon(Icons.lock_outline, size: 16, color: Color(0xFF9CA3AF)),
            suffixIcon: IconButton(
              icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, size: 16),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          validator: (value) {
            if (value == null || value.length < 8) {
              return 'Password must be at least 8 characters';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildConfirmPasswordField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Confirm Password', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        TextFormField(
          controller: _confirmPasswordController,
          obscureText: _obscureConfirmPassword,
          decoration: InputDecoration(
            hintText: 'Confirm your password',
            prefixIcon: const Icon(Icons.lock_outline, size: 16, color: Color(0xFF9CA3AF)),
            suffixIcon: IconButton(
              icon: Icon(_obscureConfirmPassword ? Icons.visibility_off : Icons.visibility, size: 16),
              onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          validator: (value) {
            if (value != _passwordController.text) return 'Passwords do not match';
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildPrimaryButton() {
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handleSubmit,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1DA1F2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: _isLoading
            ? const CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.white))
            : Text(widget.mode == AuthMode.signin ? 'Sign In' : 'Create Account'),
      ),
    );
  }

  Widget _buildFooter() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(widget.mode == AuthMode.signin ? "Don't have an account? " : "Already have an account? "),
        GestureDetector(
          onTap: _switchMode,
          child: Text(
            widget.mode == AuthMode.signin ? 'Sign Up' : 'Sign In',
            style: const TextStyle(color: Color(0xFF29ABE2), decoration: TextDecoration.underline),
          ),
        ),
      ],
    );
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      if (widget.mode == AuthMode.signin) {
        await AppwriteService.signIn(_emailController.text, _passwordController.text);
      } else {
        // Normalize username: strip leading @ if user typed it, store plain handle.
        final raw = _usernameController.text.trim();
        final handle = raw.startsWith('@') ? raw.substring(1) : raw;
        await AppwriteService.signUp(
          _emailController.text,
          _passwordController.text,
          handle,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthWrapper()),
        (route) => false,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _switchMode() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => AuthForm(
          mode: widget.mode == AuthMode.signin ? AuthMode.signup : AuthMode.signin,
        ),
      ),
    );
  }

  void _openApp() {
    if (!kIsWeb) return;
    const schemeUrl = 'xapzap://auth';
    html.window.location.href = schemeUrl;
  }

  void _openStore() {
    if (!kIsWeb) return;
    const storeUrl = 'https://play.google.com/store/apps/details?id=com.xapzap.xap';
    html.window.location.href = storeUrl;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _usernameController.dispose();
    super.dispose();
  }
}
