import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../homework/models/homework_model.dart';
import '../models/announcement_model.dart';

class AnnouncementsListScreen extends StatelessWidget {
  const AnnouncementsListScreen({super.key});

  static final List<AnnouncementModel> _sampleAnnouncements = [
    AnnouncementModel(
      id: 'ann-1',
      title: 'Annual Sports Day Schedule & Parental Consent',
      content:
          'We are excited to announce our Annual Sports Day scheduled for October 15th. Please download the attached PDF consent slip and submit the signed copy to your class teacher by next Monday.',
      priority: 'urgent',
      targetAudience: 'All Parents & Students',
      authorName: 'Principal Office',
      createdAt: DateTime.now().subtract(const Duration(hours: 3)),
      attachments: [
        const AttachmentModel(
          id: 'att-sports-1',
          fileName: 'Sports_Day_Consent_Form_2026.pdf',
          fileUrl: 'https://example.com/files/sports_consent.pdf',
          fileType: 'pdf',
          fileSize: 450000,
        ),
      ],
    ),
    AnnouncementModel(
      id: 'ann-2',
      title: 'Mid-Term Examination Dates & Syllabus',
      content:
          'Mid-term examinations will commence from September 25th. The detailed date sheet and syllabus breakdown across all subjects are available on the portal and attached below.',
      priority: 'normal',
      targetAudience: 'Classes 6 to 10',
      authorName: 'Academic Examination Board',
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
      attachments: [
        const AttachmentModel(
          id: 'att-exam-1',
          fileName: 'MidTerm_Datesheet_Class6_10.pdf',
          fileUrl: 'https://example.com/files/midterm_datesheet.pdf',
          fileType: 'pdf',
          fileSize: 820000,
        ),
      ],
    ),
    AnnouncementModel(
      id: 'ann-3',
      title: 'School Closure: National Holiday Notice',
      content:
          'Please note that the school and administrative offices will remain closed on Friday on account of the National Holiday. Regular classes will resume on Monday.',
      priority: 'normal',
      targetAudience: 'All Staff & Students',
      authorName: 'Administration Office',
      createdAt: DateTime.now().subtract(const Duration(days: 3)),
      attachments: [],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('School Announcements'),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _sampleAnnouncements.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final notice = _sampleAnnouncements[index];
          return _buildAnnouncementCard(context, notice);
        },
      ),
    );
  }

  Widget _buildAnnouncementCard(BuildContext context, AnnouncementModel notice) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row (Priority + Target Audience)
            Row(
              children: [
                if (notice.isUrgent) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.warning_amber_rounded, size: 14, color: AppColors.error),
                        SizedBox(width: 4),
                        Text(
                          'URGENT NOTICE',
                          style: TextStyle(
                            color: AppColors.error,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    notice.targetAudience,
                    style: const TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Title
            Text(
              notice.title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),

            // Body
            Text(
              notice.content,
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 12),

            // Footer (Author & Date)
            Row(
              children: [
                const Icon(Icons.account_balance_outlined, size: 15, color: AppColors.textMuted),
                const SizedBox(width: 4),
                Text(
                  notice.authorName,
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
                const Spacer(),
                Text(
                  '${notice.createdAt.day}/${notice.createdAt.month}/${notice.createdAt.year}',
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ],
            ),

            // Attachments
            if (notice.attachments.isNotEmpty) ...[
              const Divider(height: 20),
              ...notice.attachments.map((att) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.picture_as_pdf, color: AppColors.error, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          att.fileName,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.file_download_outlined, size: 20, color: AppColors.primary),
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Downloading circular: ${att.fileName}')),
                          );
                        },
                      ),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}
