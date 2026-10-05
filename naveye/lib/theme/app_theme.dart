import 'package:flutter/material.dart';

class AppColors {
  static const Color background = Color(0xFF000000); // Strict Pure Black
  static const Color surface = Color(0xFF121212);    // Dark neutral surface
  static const Color yellow = Color(0xFFFFFFFF);     // High contrast pure white
  static const Color green = Color(0xFFFFFFFF);      // High contrast pure white
  static const Color white = Color(0xFFFFFFFF);      // Pure white
  static const Color black = Color(0xFF000000);      // Pure black
  static const Color grey = Color(0xFFB0B0B0);       // Accessible secondary light gray
  static const Color greyLight = Color(0xFFE0E0E0);  // High-contrast secondary
  static const Color greyDark = Color(0xFF262626);   // Dark gray for borders/dividers
  static const Color inputBg = Color(0xFF1A1A1A);
  static const Color danger = Color(0xFFFFFFFF);     // High contrast white
}

class AppTheme {
  static ThemeData get dark {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.white,
        secondary: AppColors.greyLight,
        surface: AppColors.surface,
        onPrimary: AppColors.black,
        onSurface: AppColors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.white),
        titleTextStyle: TextStyle(color: AppColors.white, fontSize: 20, fontWeight: FontWeight.w700),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.white,
          foregroundColor: AppColors.black,
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.inputBg,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.greyDark, width: 1.5)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.greyDark, width: 1.5)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.white, width: 2.0)),
        hintStyle: const TextStyle(color: AppColors.grey, fontSize: 16),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      ),
    );
  }
}
