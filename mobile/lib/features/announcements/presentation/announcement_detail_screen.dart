import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
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
                Text(
                  formattedDate,
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.group_outlined, size: 16, color: AppColors.textMuted),
                const SizedBox(width: 6),
                Text(
                  announcement.audienceLabel,
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
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

            // Attachment Card
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
                      color: const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.picture_as_pdf, color: Color(0xFFEF4444), size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'exam_schedule.pdf',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          '2.4 MB',
                          style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.download_rounded, color: AppColors.primary),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Downloading exam_schedule.pdf...')),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // Author Footer
            Row(
              children: [
                const CircleAvatar(
                  radius: 14,
                  backgroundImage: NetworkImage('https://images.unsplash.com/photo-1544005313-94ddf0286df2?w=100'),
                ),
                const SizedBox(width: 8),
                Text(
                  'Posted by: ${announcement.createdByName}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
