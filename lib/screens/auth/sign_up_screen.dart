import 'package:flutter/material.dart';
import 'auth_form.dart';

class SignUpScreen extends StatelessWidget {
  const SignUpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AuthForm(mode: AuthMode.signup);
  }
}