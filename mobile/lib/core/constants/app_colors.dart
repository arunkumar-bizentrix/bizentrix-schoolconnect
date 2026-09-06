import 'package:flutter/material.dart';

/// Centralized color palette for Bizentrix SchoolConnect.
class AppColors {
  // Brand Primary & Secondary
  static const Color primary = Color(0xFF1E3A8A); // Deep Royal Blue
  static const Color primaryLight = Color(0xFF3B82F6);
  static const Color primaryDark = Color(0xFF172554);

  static const Color secondary = Color(0xFF0D9488); // Modern Teal
  static const Color accent = Color(0xFFF59E0B); // Warm Amber

  // Background & Surface
  static const Color background = Color(0xFFF8FAFC); // Slate 50
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceElevated = Color(0xFFF1F5F9); // Slate 100

  // Text colors
  static const Color textPrimary = Color(0xFF0F172A); // Slate 900
  static const Color textSecondary = Color(0xFF475569); // Slate 600
  static const Color textMuted = Color(0xFF94A3B8); // Slate 400

  // Role-specific badge & highlight colors
  static const Color roleAdmin = Color(0xFF7C3AED); // Violet
  static const Color roleTeacher = Color(0xFF0284C7); // Sky Blue
  static const Color roleParent = Color(0xFF059669); // Emerald Green

  // Status & Feedback colors
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);

  // Border & Divider
  static const Color border = Color(0xFFE2E8F0); // Slate 200
  static const Color divider = Color(0xFFE2E8F0);
}
