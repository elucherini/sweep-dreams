import 'package:flutter/material.dart';

class AppTheme {
  // Cool-neutral editorial palette (2026): calm, restrained, and durable.
  // Background: slightly lower-key than pure near-white so glass can separate.
  // (Still cool-neutral + editorial.)
  static const Color backgroundTop = Color(0xFFF2F4FA);
  static const Color backgroundBottom = Color(0xFFDDE2EE);

  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [backgroundTop, backgroundBottom],
  );

  // Background structure (used by `EditorialBackground`).
  // Keep these very soft: they exist to create enough structure for blur distortion.
  static const Color backgroundBlobPeriwinkle = Color(0xFFB9C2FF);
  static const Color backgroundBlobSky = Color(0xFFAED9FF);
  static const double backgroundBlobBlurSigma = 60; // target ≈ 60
  // A lighter-blur “detail” component so the glass blur has something to affect.
  // This stays very low opacity so it reads as structure, not decoration.
  static const double backgroundBlobDetailBlurSigma = 10;
  static const double backgroundBlobDetailOpacityScale = 0.62;
  // Slightly higher within spec to ensure the frosted blur has enough structure.
  // Dialed down from the previous max to reduce overall luminance while staying in-spec.
  static const double backgroundBlobOpacityA = 0.32; // target ≈ 0.28–0.35
  static const double backgroundBlobOpacityB = 0.31; // target ≈ 0.28–0.35
  static const double backgroundGrainOpacity = 0.026; // reduced ~25% from 0.035

  // Background "focus field" (luminance-only) to help frosted materials read.
  // This is intentionally subtle: it should not look like a visible gradient.
  static const double backgroundFocusFieldOpacity = 0.085;
  static const double backgroundFocusFieldBlurSigma = 120;
  static const double backgroundFocusFieldWidthFactor = 1.05;
  static const double backgroundFocusFieldHeightFactor = 0.52;
  static const Alignment backgroundFocusFieldAlignment = Alignment(0.0, 0.18);

  // Primary / accents stay cool and slightly desaturated.
  static const Color primaryColor = Color(0xFF4F63F6); // muted periwinkle-indigo
  static const Color primarySoft = Color(0xFFDDE3FF); // cool tint for chips/badges
  static const Color accent = Color(0xFF7AA9FF); // desaturated sky accent

  // Surfaces
  static const Color surface = Color(0xFFFFFFFF);
  // A cooler paper-white for nested surfaces inside glass. Avoid warm off-whites.
  static const Color surfaceSoft = Color(0xFFFBFCFF);

  // Text (cool slate, not purple)
  static const Color textPrimary = Color(0xFF0F172A); // slate-900
  static const Color textMuted = Color(0xFF64748B); // slate-500
  static const Color border = Color(0xFFD3DAE8); // cool gray border

  // Status
  static const Color success = Color(0xFF4F63F6); // aligned with primary
  static const Color error = Color(0xFFF43F5E); // rose-500
  static const Color successBackground = Color(0xFFE6EBFF); // cool tint
  static const Color errorBackground = Color(0xFFFFE4E6); // rose-100

  // Layout
  static const double screenPadding = 12.0;
  static const double maxContentWidth = 1200.0;
  static const double cardPadding = 12.0;

  // Frosted glass defaults (used by `FrostedCard`).
  // Glass: tuned for a more contemporary (2025/6) read: clearer center + stronger blur.
  static const Color glassBase = Color(0xFFF2F5FC);
  static const double glassOpacity = 0.62;
  static const double glassBlurSigma = 24;
  static const double glassRadius = 20; // target ≈ 20
  static const double glassInnerStrokeOpacity = 0.26;
  static const double glassInnerStrokeWidth = 1.0;
  static const double glassInnerStrokeInset = 1.0; // padding for the inner stroke
  static const double glassShadowOpacity = 0.085;
  static const double glassShadowBlurRadius = 40;
  static const Offset glassShadowOffset = Offset(0, 14);
  // Internal light falloff (adds thickness without glossy highlights).
  static const double glassTopHighlightOpacity = 0.10;
  static const double glassBottomShadeOpacity = 0.04;
  // Outer edge definition (subtle, cool gray; avoids "glow" look).
  static const double glassOuterStrokeOpacity = 0.26;
  static const double glassOuterStrokeWidth = 0.95;
  // Edge vignette (very subtle) to help the sheet read against light backgrounds.
  static const double glassEdgeVignetteOpacity = 0.0;

  // "Paper" surfaces nested inside glass should stay readable but not fully opaque,
  // otherwise they visually replace the glass layer.
  static const double paperInGlassOpacity = 0.84;

  static ThemeData get lightTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primaryColor,
      brightness: Brightness.light,
      error: error,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: backgroundTop,

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
          color: Colors.white,
        ),
      ),

      // Card theme
      cardTheme: CardThemeData(
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        color: colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.35),
            width: 0.8,
          ),
        ),
      ),

      // Elevated button theme - warm off-white surface like location button
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return const Color(0xFFFAF9F7).withValues(alpha: 0.6);
            }
            return const Color(0xFFFAF9F7); // warm off-white
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return const Color(0xFF1A1A1A).withValues(alpha: 0.5);
            }
            return const Color(0xFF1A1A1A); // near-black text
          }),
          elevation: WidgetStateProperty.all(0),
          shadowColor: WidgetStateProperty.all(Colors.transparent),
          surfaceTintColor: WidgetStateProperty.all(Colors.transparent),
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          ),
          minimumSize: WidgetStateProperty.all(const Size.fromHeight(56)),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: Colors.black.withValues(alpha: 0.06),
                width: 1,
              ),
            ),
          ),
          textStyle: WidgetStateProperty.all(
            const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),

      // Tonal filled buttons for secondary actions
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colorScheme.primaryContainer,
          foregroundColor: colorScheme.onPrimaryContainer,
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),

      // Chip theme with enhanced selection
      chipTheme: ChipThemeData(
        backgroundColor:
            colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        selectedColor: colorScheme.secondaryContainer,
        labelStyle: TextStyle(
          fontWeight: FontWeight.w600,
          color: colorScheme.onSurface,
        ),
        secondaryLabelStyle: TextStyle(
          fontWeight: FontWeight.w700,
          color: colorScheme.onSecondaryContainer,
        ),
        selectedShadowColor: Colors.transparent,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.35),
            width: 0.8,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        elevation: 0,
      ),

      // List tiles with softer padding/shape
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        tileColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
        selectedTileColor: colorScheme.secondaryContainer,
        selectedColor: colorScheme.onSecondaryContainer,
      ),
    );
  }
}
