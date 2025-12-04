
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static final ThemeData lightTheme = ThemeData(
    brightness: Brightness.light,
    primarySwatch: Colors.blue,
    primaryColor: const Color(0xFF1DA1F2),
    scaffoldBackgroundColor: Colors.white,
    textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: Colors.black,
      elevation: 0,
      surfaceTintColor: Colors.white,
    ),
    cardColor: Colors.white,
    dividerColor: const Color(0xFFE5E7EB),
    iconTheme: const IconThemeData(color: Color(0xFF6B7280)),
  );

  static final ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    primarySwatch: Colors.blue,
    primaryColor: const Color(0xFF1DA1F2),
    scaffoldBackgroundColor: const Color(0xFF121212),
    textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme).apply(
      bodyColor: Colors.white,
      displayColor: Colors.white,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF1F1F1F),
      foregroundColor: Colors.white,
      elevation: 0,
      surfaceTintColor: Color(0xFF1F1F1F),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Color(0xFF1F1F1F),
      selectedItemColor: Colors.white,
      unselectedItemColor: Color(0xFF9CA3AF),
    ),
    cardColor: const Color(0xFF1F1F1F),
    dividerColor: const Color(0xFF374151),
    iconTheme: const IconThemeData(color: Color(0xFF9CA3AF)),
  );
}
