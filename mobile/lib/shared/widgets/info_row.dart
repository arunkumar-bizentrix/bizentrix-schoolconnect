import 'package:flutter/material.dart';

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
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 16, color: colors.onSurfaceVariant),
        SizedBox(width: spacing),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
        ),
        const Spacer(),
        // A long value (school name, address, URL) shortens instead of
        // pushing the row past its width.
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: valueFontSize,
              fontWeight: FontWeight.w600,
              color: colors.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}
