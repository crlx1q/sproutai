import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Палитра «Botanical Modern» из DESIGN.md.
class AppColors {
  static const surface = Color(0xFFF9F9F8);
  static const surfaceContainerLow = Color(0xFFF3F4F3);
  static const surfaceContainer = Color(0xFFEDEEED);
  static const surfaceContainerHigh = Color(0xFFE7E8E7);
  static const white = Color(0xFFFFFFFF);
  static const onSurface = Color(0xFF191C1C);
  static const onSurfaceVariant = Color(0xFF414844);
  static const outline = Color(0xFF717973);
  static const outlineVariant = Color(0xFFC1C8C2);

  static const primary = Color(0xFF012D1D);
  static const primaryContainer = Color(0xFF1B4332);
  static const onPrimaryContainer = Color(0xFF86AF99);
  static const primaryFixedDim = Color(0xFFA5D0B9);

  static const secondary = Color(0xFF3E6750);
  static const secondaryContainer = Color(0xFFBDEACD);
  static const mintSoft = Color(0xFFD9EFE2);
  static const sage = Color(0xFFEEF4F0);

  static const terracotta = Color(0xFF741B04);
  static const terracottaContainer = Color(0xFFFFDAD2);
  static const error = Color(0xFFBA1A1A);

  static const cardShadow = Color(0x141B4332);
}

class AppTheme {
  static ThemeData light() {
    final baseText = GoogleFonts.workSansTextTheme();
    final textTheme = baseText.copyWith(
      displayLarge: GoogleFonts.literata(
        fontSize: 40, fontWeight: FontWeight.w700, height: 1.2,
        letterSpacing: -0.8, color: AppColors.primary,
      ),
      headlineLarge: GoogleFonts.literata(
        fontSize: 28, fontWeight: FontWeight.w600, height: 1.28,
        color: AppColors.primary,
      ),
      headlineMedium: GoogleFonts.literata(
        fontSize: 24, fontWeight: FontWeight.w500, height: 1.33,
        color: AppColors.primary,
      ),
      titleLarge: GoogleFonts.literata(
        fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.onSurface,
      ),
      titleMedium: GoogleFonts.literata(
        fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.onSurface,
      ),
      bodyLarge: GoogleFonts.workSans(
        fontSize: 17, height: 1.55, color: AppColors.onSurface,
      ),
      bodyMedium: GoogleFonts.workSans(
        fontSize: 15, height: 1.5, color: AppColors.onSurfaceVariant,
      ),
      labelLarge: GoogleFonts.workSans(
        fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.7,
        color: AppColors.onSurfaceVariant,
      ),
      labelSmall: GoogleFonts.workSans(
        fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.outline,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.surface,
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        onPrimary: Colors.white,
        primaryContainer: AppColors.primaryContainer,
        onPrimaryContainer: AppColors.primaryFixedDim,
        secondary: AppColors.secondary,
        onSecondary: Colors.white,
        secondaryContainer: AppColors.secondaryContainer,
        onSecondaryContainer: AppColors.secondary,
        tertiary: AppColors.terracotta,
        tertiaryContainer: AppColors.terracottaContainer,
        onTertiaryContainer: AppColors.terracotta,
        error: AppColors.error,
        surface: AppColors.surface,
        onSurface: AppColors.onSurface,
        onSurfaceVariant: AppColors.onSurfaceVariant,
        outline: AppColors.outline,
        outlineVariant: AppColors.outlineVariant,
      ),
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.literata(
          fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.primary,
        ),
        iconTheme: const IconThemeData(color: AppColors.onSurface),
      ),
      cardTheme: const CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(24)),
        ),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: GoogleFonts.workSans(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary, width: 1.4),
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: GoogleFonts.workSans(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.secondary,
          textStyle: GoogleFonts.workSans(fontSize: 14.5, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.primaryContainer, width: 1.6),
        ),
        hintStyle: GoogleFonts.workSans(color: AppColors.outline, fontSize: 15),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.primaryContainer,
        contentTextStyle: GoogleFonts.workSans(color: Colors.white, fontSize: 14.5),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.surfaceContainerHigh),
    );
  }
}

/// Мягкая «зелёная» тень для карточек из дизайн-системы.
List<BoxShadow> softShadow() => const [
      BoxShadow(
        color: AppColors.cardShadow,
        blurRadius: 30,
        offset: Offset(0, 10),
      ),
    ];
