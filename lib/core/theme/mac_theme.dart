import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../constants/app_colors.dart';

class MacTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      primaryColor: AppColors.neonViolet,
      canvasColor: AppColors.background,
      cardColor: AppColors.surface,
      dividerColor: AppColors.border,
      textTheme: GoogleFonts.interTextTheme(
        ThemeData.dark().textTheme.copyWith(
          displayLarge: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            letterSpacing: -0.5,
          ),
          titleLarge: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
            letterSpacing: -0.3,
          ),
          titleMedium: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
          bodyLarge: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: AppColors.textPrimary,
          ),
          bodyMedium: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w400,
            color: AppColors.textSecondary,
          ),
          bodySmall: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: AppColors.textMuted,
          ),
        ),
      ),
      colorScheme: const ColorScheme.dark(
        primary: AppColors.neonViolet,
        secondary: AppColors.electricCobalt,
        surface: AppColors.surface,
        background: AppColors.background,
        error: AppColors.statusAlert,
      ),
    );
  }

  /// Decoração de card com visual de vidro fosco (Glassmorphism Mac).
  static BoxDecoration glassCardDecoration({
    bool isSelected = false,
    bool isHovered = false,
    double borderRadius = 14.0,
  }) {
    return BoxDecoration(
      color: isSelected
          ? AppColors.surfaceElevated
          : (isHovered ? AppColors.surfaceHover : AppColors.surface),
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(
        color: isSelected
            ? AppColors.neonViolet
            : (isHovered ? AppColors.borderHighlight : AppColors.border),
        width: isSelected ? 1.5 : 1.0,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.45),
          blurRadius: isSelected ? 20 : 12,
          offset: const Offset(0, 6),
        ),
        if (isSelected)
          BoxShadow(
            color: AppColors.neonViolet.withOpacity(0.2),
            blurRadius: 16,
            spreadRadius: 1,
          ),
      ],
    );
  }

  /// Botão estilo pílula do macOS.
  static ButtonStyle macPillButtonStyle({bool isPrimary = true}) {
    return ElevatedButton.styleFrom(
      backgroundColor: isPrimary ? AppColors.neonViolet : AppColors.surfaceElevated,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isPrimary ? Colors.transparent : AppColors.border,
          width: 1,
        ),
      ),
    );
  }
}
