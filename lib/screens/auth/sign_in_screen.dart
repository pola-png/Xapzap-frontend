import 'package:flutter/material.dart';
import 'auth_form.dart';

class SignInScreen extends StatelessWidget {
  const SignInScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AuthForm(mode: AuthMode.signin);
  }
}
