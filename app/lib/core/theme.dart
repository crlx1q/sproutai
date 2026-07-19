import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Палитра «Botanical Modern» из DESIGN.md.
class AppColors {
  // --- Светлая тема ---
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

  // --- Тёмная тема ---
  static const darkSurface = Color(0xFF0F1512);
  static const darkSurfaceContainerLow = Color(0xFF161D18);
  static const darkSurfaceContainer = Color(0xFF1B231E);
  static const darkSurfaceContainerHigh = Color(0xFF212A24);
  static const darkCard = Color(0xFF1A221D);
  static const darkOnSurface = Color(0xFFE7ECE7);
  static const darkOnSurfaceVariant = Color(0xFFBDC7BF);
  static const darkOutline = Color(0xFF8A938B);
  static const darkOutlineVariant = Color(0xFF3F4A43);
  static const darkPrimary = Color(0xFFA5D0B9);
  static const darkOnPrimary = Color(0xFF07281A);
  static const darkSecondaryContainer = Color(0xFF244634);
  static const darkOnSecondaryContainer = Color(0xFFBDEACD);
  static const darkTertiary = Color(0xFFFFB4A3);
  static const darkTertiaryContainer = Color(0xFF5A1B0A);
}

class AppTheme {
  static TextTheme _textTheme({
    required Color heading,
    required Color strong,
    required Color body,
    required Color faint,
  }) {
    final base = GoogleFonts.workSansTextTheme();
    return base.copyWith(
      displayLarge: GoogleFonts.literata(
        fontSize: 40, fontWeight: FontWeight.w700, height: 1.2,
        letterSpacing: -0.8, color: heading,
      ),
      headlineLarge: GoogleFonts.literata(
        fontSize: 28, fontWeight: FontWeight.w600, height: 1.28, color: heading,
      ),
      headlineMedium: GoogleFonts.literata(
        fontSize: 24, fontWeight: FontWeight.w500, height: 1.33, color: heading,
      ),
      titleLarge: GoogleFonts.literata(
        fontSize: 20, fontWeight: FontWeight.w600, color: strong,
      ),
      titleMedium: GoogleFonts.literata(
        fontSize: 17, fontWeight: FontWeight.w600, color: strong,
      ),
      bodyLarge: GoogleFonts.workSans(fontSize: 17, height: 1.55, color: strong),
      bodyMedium: GoogleFonts.workSans(fontSize: 15, height: 1.5, color: body),
      labelLarge: GoogleFonts.workSans(
        fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.7, color: body,
      ),
      labelSmall: GoogleFonts.workSans(
        fontSize: 12, fontWeight: FontWeight.w500, color: faint,
      ),
    );
  }

  static ThemeData light() {
    final textTheme = _textTheme(
      heading: AppColors.primary,
      strong: AppColors.onSurface,
      body: AppColors.onSurfaceVariant,
      faint: AppColors.outline,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
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

  static ThemeData dark() {
    final textTheme = _textTheme(
      heading: AppColors.darkOnSurface,
      strong: AppColors.darkOnSurface,
      body: AppColors.darkOnSurfaceVariant,
      faint: AppColors.darkOutline,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.darkSurface,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.darkPrimary,
        onPrimary: AppColors.darkOnPrimary,
        primaryContainer: AppColors.primaryContainer,
        onPrimaryContainer: AppColors.primaryFixedDim,
        secondary: AppColors.darkPrimary,
        onSecondary: AppColors.darkOnPrimary,
        secondaryContainer: AppColors.darkSecondaryContainer,
        onSecondaryContainer: AppColors.darkOnSecondaryContainer,
        tertiary: AppColors.darkTertiary,
        tertiaryContainer: AppColors.darkTertiaryContainer,
        onTertiaryContainer: AppColors.terracottaContainer,
        error: Color(0xFFFFB4AB),
        surface: AppColors.darkSurface,
        onSurface: AppColors.darkOnSurface,
        onSurfaceVariant: AppColors.darkOnSurfaceVariant,
        outline: AppColors.darkOutline,
        outlineVariant: AppColors.darkOutlineVariant,
      ),
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.darkSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.literata(
          fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.darkOnSurface,
        ),
        iconTheme: const IconThemeData(color: AppColors.darkOnSurface),
      ),
      cardTheme: const CardThemeData(
        color: AppColors.darkCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(24)),
        ),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.darkPrimary,
          foregroundColor: AppColors.darkOnPrimary,
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: GoogleFonts.workSans(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.darkPrimary,
          side: const BorderSide(color: AppColors.darkPrimary, width: 1.4),
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: GoogleFonts.workSans(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.darkPrimary,
          textStyle: GoogleFonts.workSans(fontSize: 14.5, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.darkSurfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.darkPrimary, width: 1.6),
        ),
        hintStyle: GoogleFonts.workSans(color: AppColors.darkOutline, fontSize: 15),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.darkSurfaceContainerHigh,
        contentTextStyle: GoogleFonts.workSans(color: AppColors.darkOnSurface, fontSize: 14.5),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.darkOutlineVariant),
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
