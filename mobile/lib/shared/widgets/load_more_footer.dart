import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';

/// Footer for a paged list: shows how many of the total are loaded and pulls
/// the next page. Without it a screen silently stops at the first 20 rows.
class LoadMoreFooter extends StatelessWidget {
  const LoadMoreFooter({
    super.key,
    required this.loadedCount,
    required this.totalCount,
    required this.hasMore,
    required this.isLoading,
    required this.onLoadMore,
    this.noun = 'records',
  });

  final int loadedCount;
  final int totalCount;
  final bool hasMore;
  final bool isLoading;
  final VoidCallback onLoadMore;
  final String noun;

  @override
  Widget build(BuildContext context) {
    if (loadedCount == 0) return const SizedBox.shrink();

    // Everything is on screen: just say so, quietly.
    if (!hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text(
            totalCount > 0
                ? 'All $totalCount $noun'
                : 'All $loadedCount $noun',
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        children: [
          Text(
            'Showing $loadedCount of $totalCount $noun',
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 40,
            child: OutlinedButton.icon(
              onPressed: isLoading ? null : onLoadMore,
              icon: isLoading
                  ? const SizedBox(
                      height: 14,
                      width: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.expand_more_rounded, size: 18),
              label: Text(isLoading ? 'Loading…' : 'Load more'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
