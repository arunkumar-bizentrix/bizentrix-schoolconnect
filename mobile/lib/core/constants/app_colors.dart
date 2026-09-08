import 'package:flutter/material.dart';

/// Exact design system color tokens matching SchoolConnect reference mockups.
class AppColors {
  // Brand Primary & Accent
  static const Color primary = Color(0xFF1A62E8); // Vibrant Royal Blue
  static const Color primaryLight = Color(0xFF3B82F6);
  static const Color primaryDark = Color(0xFF0F2E6B);
  static const Color secondary = Color(0xFF0D9488); // Teal
  static const Color accent = Color(0xFFF59E0B); // Amber
  static const Color warning = Color(0xFFF59E0B); // Warning Amber
  static const Color error = Color(0xFFDC2626); // Error Red

  // Role Badges & Highlights
  static const Color roleAdmin = Color(0xFF6366F1);
  static const Color roleTeacher = Color(0xFF0284C7);
  static const Color roleParent = Color(0xFF16A34A);

  // Background & Surface
  static const Color background = Color(0xFFF8FAFC); // Slate 50
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceElevated = Color(0xFFF1F5F9); // Slate 100

  // Text Colors
  static const Color textPrimary = Color(0xFF0F172A); // Slate 900
  static const Color textSecondary = Color(0xFF475569); // Slate 600
  static const Color textMuted = Color(0xFF94A3B8); // Slate 400

  // Borders & Dividers
  static const Color border = Color(0xFFE2E8F0); // Slate 200
  static const Color divider = Color(0xFFE2E8F0);

  // 4 Dashboard Stat Card Palettes (Background & Icon/Text)
  static const Color statClassesBg = Color(0xFFE0F2FE); // Cyan / Sky Blue
  static const Color statClassesText = Color(0xFF0284C7);

  static const Color statStudentsBg = Color(0xFFDCFCE7); // Emerald Green
  static const Color statStudentsText = Color(0xFF16A34A);

  static const Color statHomeworkBg = Color(0xFFFEF3C7); // Warm Amber
  static const Color statHomeworkText = Color(0xFFD97706);

  static const Color statAnnouncementsBg = Color(0xFFF3E8FF); // Violet / Purple
  static const Color statAnnouncementsText = Color(0xFF9333EA);

  // Priority Badges (Announcements)
  static const Color priorityUrgentText = Color(0xFFDC2626); // Red
  static const Color priorityUrgentBg = Color(0xFFFEE2E2);

  static const Color priorityImportantText = Color(0xFF7C3AED); // Purple
  static const Color priorityImportantBg = Color(0xFFEDE9FE);

  static const Color priorityNormalText = Color(0xFF2563EB); // Blue
  static const Color priorityNormalBg = Color(0xFFDBEAFE);

  // Status Chips
  static const Color statusActiveText = Color(0xFF15803D);
  static const Color statusActiveBg = Color(0xFFDCFCE7);

  static const Color statusOverdueText = Color(0xFFDC2626);
  static const Color statusOverdueBg = Color(0xFFFEE2E2);

  // Subject Icon Backgrounds
  static const Color mathIconBg = Color(0xFFFEE2E2);
  static const Color mathIconColor = Color(0xFFEF4444);

  static const Color scienceIconBg = Color(0xFFDCFCE7);
  static const Color scienceIconColor = Color(0xFF16A34A);

  static const Color englishIconBg = Color(0xFFDBEAFE);
  static const Color englishIconColor = Color(0xFF2563EB);

  static const Color socialIconBg = Color(0xFFFEF3C7);
  static const Color socialIconColor = Color(0xFFD97706);

  static const Color defaultIconBg = Color(0xFFF3E8FF);
  static const Color defaultIconColor = Color(0xFF9333EA);
}
