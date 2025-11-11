import 'package:capstone_app/ui/theme/branding.dart';
import 'package:flutter/material.dart';

ThemeData lightTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: kPrimary,
    brightness: Brightness.light,
  );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFFF8FAFC),
    useMaterial3: true,
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

ThemeData darkTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: kPrimary,
    brightness: Brightness.dark,
  );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFF18181B),
    useMaterial3: true,
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}