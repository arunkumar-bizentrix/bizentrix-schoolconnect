import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../models/announcement_model.dart';

class AnnouncementDetailScreen extends StatelessWidget {
  final AnnouncementModel announcement;

  const AnnouncementDetailScreen({super.key, required this.announcement});

  @override
  Widget build(BuildContext context) {
    final formattedDate = DateFormat('MMM dd, yyyy • hh:mm a').format(announcement.publishedAt);

    Color priorityText;
    Color priorityBg;
    if (announcement.isUrgent) {
      priorityText = AppColors.priorityUrgentText;
      priorityBg = AppColors.priorityUrgentBg;
    } else if (announcement.isImportant) {
      priorityText = AppColors.priorityImportantText;
      priorityBg = AppColors.priorityImportantBg;
    } else {
      priorityText = AppColors.priorityNormalText;
      priorityBg = AppColors.priorityNormalBg;
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Announcement Details',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Priority Tag
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: priorityBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                announcement.priority.toUpperCase(),
                style: TextStyle(
                  color: priorityText,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Title
            Text(
              announcement.title,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 14),

            // Meta Info (Date & Audience)
            Row(
              children: [
                const Icon(Icons.calendar_today_outlined, size: 15, color: AppColors.textMuted),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    formattedDate,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.group_outlined, size: 16, color: AppColors.textMuted),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    announcement.audienceLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Divider(color: AppColors.border),
            const SizedBox(height: 16),

            // Content Body
            Text(
              announcement.content,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textPrimary,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 24),

            // Attachment card - only when the announcement actually has one.
            // (It used to always render a hard-coded "exam_schedule.pdf".)
            if (announcement.attachmentUrl != null &&
                announcement.attachmentUrl!.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.mathIconBg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        _isImage(announcement.attachmentUrl!)
                            ? Icons.image_outlined
                            : Icons.picture_as_pdf,
                        color: AppColors.mathIconColor,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _fileName(announcement.attachmentUrl!),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Tap to copy the link',
                            style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Copy attachment link',
                      icon: const Icon(Icons.link_rounded, color: AppColors.primary),
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: announcement.attachmentUrl!),
                        );
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Attachment link copied')),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
            ],

            // Author Footer
            Row(
              children: [
                UserAvatar(
                  radius: 14,
                  initials: _authorInitials(announcement.createdByName),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Posted by: ${announcement.createdByName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  /// Last path segment of an attachment URL, used as its display name.
  static String _fileName(String url) {
    final clean = url.split('?').first;
    final parts = clean.split('/');
    return parts.isEmpty || parts.last.isEmpty ? 'Attachment' : parts.last;
  }

  static bool _isImage(String url) {
    final lower = url.toLowerCase().split('?').first;
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp');
  }

  /// Initials for the announcement author, used by the avatar placeholder.
  static String _authorInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'))
      ..removeWhere((part) => part.isEmpty);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }
}
