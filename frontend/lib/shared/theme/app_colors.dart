import 'package:flutter/material.dart';

/// Single source of truth for every color in the app.
/// Role accents are the only visual difference between role experiences.
class AppColors {
  AppColors._();

  // --- Brand / role accents -------------------------------------------------
  static const Color brandIndigo = Color(0xFF6366F1); // Patient accent
  static const Color doctorGreen = Color(0xFF057A55); // Healthworker accent
  static const Color adminPurple = Color(0xFF7E3AF2); // Admin accent
  static const Color mcareAmber = Color(0xFFE3A008); // mCare Assistant accent

  // --- Neutrals -------------------------------------------------------------
  static const Color brandInk = Color(0xFF0F172A); // Primary text
  static const Color textMutedAA = Color(0xFF64748B); // AA-contrast secondary
  static const Color textFaint = Color(0xFF94A3B8);
  static const Color border = Color(0xFFE2E8F0);
  static const Color borderStrong = Color(0xFFCBD5E1);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceAlt = Color(0xFFF8FAFC);
  static const Color surfaceMuted = Color(0xFFF1F5F9);
  static const Color scaffoldBg = Color(0xFFF6F7FB);
  static const Color overlay = Color(0x66000000);

  // --- Status (universal clinical palette) ----------------------------------
  static const Color success = Color(0xFF10B981); // Green: normal
  static const Color warning = Color(0xFFF59E0B); // Amber: warning
  static const Color critical = Color(0xFFEF4444); // Red: critical
  static const Color info = Color(0xFF3B82F6);

  // Soft tinted backgrounds for status chips
  static const Color successSoft = Color(0xFFD1FAE5);
  static const Color warningSoft = Color(0xFFFEF3C7);
  static const Color criticalSoft = Color(0xFFFEE2E2);
  static const Color infoSoft = Color(0xFFDBEAFE);

  // --- Vital accents --------------------------------------------------------
  static const Color heartRed = Color(0xFFE11D48);
  static const Color spo2Blue = Color(0xFF0EA5E9);
  static const Color bpPurple = Color(0xFF8B5CF6);
  static const Color glucoseAmber = Color(0xFFD97706);
  static const Color tempTeal = Color(0xFF14B8A6);
  static const Color respGreen = Color(0xFF22C55E);
  static const Color weightSlate = Color(0xFF475569);

  // --- Dark theme equivalents ----------------------------------------------
  // Tuned for WCAG AA contrast against darkInk text.
  static const Color darkScaffoldBg = Color(0xFF0B1120);
  static const Color darkSurface = Color(0xFF111827);
  static const Color darkSurfaceAlt = Color(0xFF1F2937);
  static const Color darkSurfaceMuted = Color(0xFF182234);
  static const Color darkBorder = Color(0xFF334155);
  static const Color darkBorderStrong = Color(0xFF475569);
  static const Color darkInk = Color(0xFFF8FAFC);          // primary text
  static const Color darkTextMuted = Color(0xFFE2E8F0);    // AA secondary
  static const Color darkTextFaint = Color(0xFFCBD5E1);    // hints/placeholders
  static const Color darkOverlay = Color(0xCC000000);

  // Soft status backgrounds for dark mode chips — slightly lifted saturation
  // so foreground accent colors remain readable.
  static const Color darkSuccessSoft = Color(0xFF065F46);
  static const Color darkWarningSoft = Color(0xFF92400E);
  static const Color darkCriticalSoft = Color(0xFF991B1B);
  static const Color darkInfoSoft = Color(0xFF1E40AF);
}

/// Resolves the right token for the current brightness so widgets don't
/// branch on `Theme.of(context).brightness` themselves.
class AppPalette {
  AppPalette._();

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color surface(BuildContext context) =>
      isDark(context) ? AppColors.darkSurface : AppColors.surface;

  static Color surfaceAlt(BuildContext context) =>
      isDark(context) ? AppColors.darkSurfaceAlt : AppColors.surfaceAlt;

  static Color surfaceMuted(BuildContext context) =>
      isDark(context) ? AppColors.darkSurfaceMuted : AppColors.surfaceMuted;

  static Color scaffoldBg(BuildContext context) =>
      isDark(context) ? AppColors.darkScaffoldBg : AppColors.scaffoldBg;

  static Color border(BuildContext context) =>
      isDark(context) ? AppColors.darkBorder : AppColors.border;

  static Color borderStrong(BuildContext context) =>
      isDark(context) ? AppColors.darkBorderStrong : AppColors.borderStrong;

  static Color ink(BuildContext context) =>
      isDark(context) ? AppColors.darkInk : AppColors.brandInk;

  static Color textMuted(BuildContext context) =>
      isDark(context) ? AppColors.darkTextMuted : AppColors.textMutedAA;

  static Color textFaint(BuildContext context) =>
      isDark(context) ? AppColors.darkTextFaint : AppColors.textFaint;

  static Color overlay(BuildContext context) =>
      isDark(context) ? AppColors.darkOverlay : AppColors.overlay;

  static Color successSoft(BuildContext context) =>
      isDark(context) ? AppColors.darkSuccessSoft : AppColors.successSoft;

  static Color warningSoft(BuildContext context) =>
      isDark(context) ? AppColors.darkWarningSoft : AppColors.warningSoft;

  static Color criticalSoft(BuildContext context) =>
      isDark(context) ? AppColors.darkCriticalSoft : AppColors.criticalSoft;

  static Color infoSoft(BuildContext context) =>
      isDark(context) ? AppColors.darkInfoSoft : AppColors.infoSoft;
}

/// Gradients used by hero cards and accent surfaces.
class AppGradients {
  AppGradients._();

  static const LinearGradient patientHero = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
  );

  static const LinearGradient doctorHero = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF057A55), Color(0xFF10B981)],
  );

  static const LinearGradient criticalAlert = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFEF4444), Color(0xFFF97316)],
  );

  static const LinearGradient successAlert = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF10B981), Color(0xFF22C55E)],
  );

  static const LinearGradient glassSurface = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFFFFF), Color(0xFFF8FAFC)],
  );
}
