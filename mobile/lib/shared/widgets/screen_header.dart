import 'package:flutter/material.dart';

/// Page heading with an optional action button on the right.
///
/// Laying this out as a plain `Row` of `Expanded(title)` + button is a trap:
/// the button is not flexible, so once its intrinsic width approaches the
/// available width the `Expanded` collapses toward zero and the title wraps
/// one letter per line. Below [stackBelowWidth] the action moves under the
/// title instead, which keeps the heading readable on small phones and in the
/// narrow web shell.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
    this.stackBelowWidth = 400,
  });

  final String title;
  final String? subtitle;
  final Widget? action;

  /// Available width under which the action is stacked beneath the title.
  final double stackBelowWidth;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: colors.onSurface,
            letterSpacing: -0.5,
          ),
        ),
        if (subtitle != null && subtitle!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );

    if (action == null) return titleBlock;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < stackBelowWidth) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              titleBlock,
              const SizedBox(height: 12),
              Align(alignment: Alignment.centerLeft, child: action),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: titleBlock),
            const SizedBox(width: 12),
            action!,
          ],
        );
      },
    );
  }
}
