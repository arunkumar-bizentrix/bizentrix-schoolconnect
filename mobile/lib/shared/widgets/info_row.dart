import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';

/// A labelled detail line: leading icon, label on the left, value on the
/// right. Used in profile details, homework details and anywhere a record's
/// fields are listed.
class InfoRow extends StatelessWidget {
  const InfoRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.valueFontSize = 13,
    this.spacing = 10,
  });

  final IconData icon;
  final String label;
  final String value;
  final double valueFontSize;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.textMuted),
        SizedBox(width: spacing),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontSize: valueFontSize,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
