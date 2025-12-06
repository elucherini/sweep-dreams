import 'package:flutter/material.dart';

class AppTheme {
  // Moonlit Streets Color Palette
  // Primary: Deep purple/indigo (night sky, street lights)
  static const Color primaryColor = Color(0xFF6366F1); // indigo-500
  static const Color primarySoft = Color(0xFFE0E7FF); // indigo-100
  static const Color accent =
      Color(0xFFFBBF24); // yellow-400 (streetlight glow)

  // Background: Soft lavender twilight
  static const Color background = Color(0xFFF5F3FF); // purple-50
  static const Color surface = Color(0xFFFFFFFF);

  // Text
  static const Color textPrimary = Color(0xFF1E1B4B); // indigo-950
  static const Color textMuted = Color(0xFF64748B); // slate-500
  static const Color border = Color(0xFFDDD6FE); // purple-200

  // Status
  static const Color success = Color(0xFF8B5CF6); // purple-500
  static const Color error = Color(0xFFF43F5E); // rose-500
  static const Color successBackground = Color(0xFFF3E8FF); // purple-100
  static const Color errorBackground = Color(0xFFFFE4E6); // rose-100

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        primary: primaryColor,
        surface: surface,
        error: error,
      ),
      scaffoldBackgroundColor: background,

      // Text theme
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: 36,
          fontWeight: FontWeight.bold,
          color: textPrimary,
          height: 1.2,
        ),
        displayMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: textPrimary,
          height: 1.3,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          color: textPrimary,
          height: 1.5,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          color: textMuted,
          height: 1.5,
        ),
        labelLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: surface,
        ),
      ),

      // Card theme
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: border, width: 1),
        ),
        color: surface,
      ),

      // Elevated button theme with glow effect
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: surface,
          elevation: 8,
          shadowColor: primaryColor.withValues(alpha: 0.5),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ),

      // Chip theme with enhanced selection
      chipTheme: ChipThemeData(
        backgroundColor: primarySoft,
        selectedColor: primaryColor,
        labelStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          color: primaryColor,
        ),
        selectedShadowColor: primaryColor.withValues(alpha: 0.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: border),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        elevation: 2,
      ),
    );
  }
}
