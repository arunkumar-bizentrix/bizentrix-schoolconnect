import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';

/// Debounced search box wired to a server-side query.
///
/// The API pages at 20 rows, so filtering the loaded page on the client would
/// only ever search that page. Every screen using this sends the term to the
/// backend and reloads.
class SearchField extends StatefulWidget {
  const SearchField({
    super.key,
    required this.hintText,
    required this.onSearch,
    this.debounce = const Duration(milliseconds: 350),
  });

  final String hintText;
  final ValueChanged<String> onSearch;
  final Duration debounce;

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  final _controller = TextEditingController();
  Timer? _debounceTimer;
  bool _hasText = false;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() => _hasText = value.isNotEmpty);
    _debounceTimer?.cancel();
    _debounceTimer = Timer(widget.debounce, () => widget.onSearch(value.trim()));
  }

  void _clear() {
    _debounceTimer?.cancel();
    _controller.clear();
    setState(() => _hasText = false);
    widget.onSearch('');
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      onChanged: _onChanged,
      textInputAction: TextInputAction.search,
      onSubmitted: (value) {
        _debounceTimer?.cancel();
        widget.onSearch(value.trim());
      },
      style: const TextStyle(fontSize: 13.5),
      decoration: InputDecoration(
        hintText: widget.hintText,
        hintStyle: const TextStyle(fontSize: 13, color: AppColors.textMuted),
        prefixIcon:
            const Icon(Icons.search_rounded, size: 20, color: AppColors.textMuted),
        suffixIcon: _hasText
            ? IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                color: AppColors.textMuted,
                tooltip: 'Clear search',
                onPressed: _clear,
              )
            : null,
        filled: true,
        fillColor: AppColors.background,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
        ),
      ),
    );
  }
}
