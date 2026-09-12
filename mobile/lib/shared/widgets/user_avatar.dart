import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';

/// Circular avatar for a user.
///
/// Shows the uploaded profile picture when there is one, and the user's
/// initials otherwise. It never falls back to a stock photo from a third-party
/// CDN - a placeholder must not look like a real person, and must not leak
/// viewer traffic to an external host.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.initials,
    this.imageUrl,
    this.radius = 20,
    this.backgroundColor = AppColors.primaryLight,
    this.foregroundColor = Colors.white,
  });

  final String initials;
  final String? imageUrl;
  final double radius;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;
    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor,
      backgroundImage: hasImage ? NetworkImage(imageUrl!) : null,
      child: hasImage
          ? null
          : Text(
              initials,
              style: TextStyle(
                color: foregroundColor,
                fontWeight: FontWeight.w700,
                fontSize: radius * 0.8,
              ),
            ),
    );
  }
}
