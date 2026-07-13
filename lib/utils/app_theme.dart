import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Midnight Azure Palette
  static const Color background = Color(0xFF0F172A);
  static const Color surface = Color(0xFF1E293B);
  static const Color primary = Color(0xFF3B82F6);
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color success = Color(0xFF81C995);
  static const Color error = Color(0xFFF28B82);

  static Color get border => Colors.white.withValues(alpha: 0.05);
  static Color get shadow => Colors.black.withValues(alpha: 0.3);

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      primaryColor: primary,
      scaffoldBackgroundColor: background,
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: primary),
        titleTextStyle: GoogleFonts.manrope(
          color: primary,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
          fontSize: 16,
        ),
      ),
      textTheme: TextTheme(
        displayLarge: GoogleFonts.manrope(fontWeight: FontWeight.bold, letterSpacing: -0.5, color: textPrimary),
        displayMedium: GoogleFonts.manrope(fontWeight: FontWeight.bold, letterSpacing: -0.5, color: textPrimary),
        displaySmall: GoogleFonts.manrope(fontWeight: FontWeight.bold, color: textPrimary),
        headlineMedium: GoogleFonts.manrope(fontWeight: FontWeight.w700, color: textPrimary),
        titleLarge: GoogleFonts.manrope(fontWeight: FontWeight.w600, color: textPrimary),
        titleMedium: GoogleFonts.manrope(fontWeight: FontWeight.w800, color: textPrimary),
        titleSmall: GoogleFonts.manrope(fontWeight: FontWeight.w700, color: textPrimary),
        bodyLarge: GoogleFonts.inter(color: textPrimary),
        bodyMedium: GoogleFonts.inter(color: textSecondary),
        bodySmall: GoogleFonts.inter(color: textSecondary),
        labelLarge: GoogleFonts.inter(fontWeight: FontWeight.w600, color: textPrimary),
      ),
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: surface,
        surface: surface,
      ),
      useMaterial3: true,
    );
  }
}
