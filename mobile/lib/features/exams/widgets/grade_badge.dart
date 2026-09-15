import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';

/// A grade as the backend computed it (A1, B2, D...), coloured by band so a
/// report card reads at a glance. Colours follow the first letter only, so a
/// school that renames its bands still gets a sensible result.
class GradeBadge extends StatelessWidget {
  const GradeBadge({super.key, required this.grade, this.onDark = false, this.large = false});

  final String? grade;
  final bool onDark;
  final bool large;

  static (Color, Color) colorsFor(String grade) {
    switch (grade.isEmpty ? '' : grade[0].toUpperCase()) {
      case 'A':
        return (AppColors.statusActiveBg, AppColors.statusActiveText);
      case 'B':
        return (AppColors.statClassesBg, AppColors.statClassesText);
      case 'C':
        return (AppColors.statHomeworkBg, AppColors.statHomeworkText);
      case 'D':
        return (AppColors.priorityImportantBg, AppColors.priorityImportantText);
      default:
        return (AppColors.statusOverdueBg, AppColors.statusOverdueText);
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = grade;
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    final (background, foreground) = colorsFor(value);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: large ? 10 : 7, vertical: large ? 4 : 2),
      decoration: BoxDecoration(
        color: onDark ? Colors.white : background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        value,
        style: TextStyle(
          fontSize: large ? 16 : 11.5,
          fontWeight: FontWeight.w800,
          color: foreground,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
