import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_colors.dart';
import '../network/api_client.dart';
import 'protected_file_io.dart' if (dart.library.js_interop) 'protected_file_web.dart' as platform;

/// Downloads a file the backend only hands to a signed-in, authorised user -
/// homework and notice attachments, report cards - and opens it.
///
/// These are never plain links: the request carries the user's token, so the
/// server re-checks on every download that this user may see this record.
/// A copied link on its own opens nothing.
Future<void> openProtectedFile(
  BuildContext context, {
  required String url,
  required String fileName,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final apiClient = ProviderScope.containerOf(context, listen: false).read(apiClientProvider);

  messenger?.showSnackBar(
    SnackBar(content: Text('Opening $fileName...'), duration: const Duration(seconds: 2)),
  );

  try {
    final response = await apiClient.dio.get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    final bytes = response.data ?? const <int>[];
    final mimeType = response.headers.value(Headers.contentTypeHeader) ?? 'application/octet-stream';
    final error = await platform.saveAndOpen(bytes, fileName, mimeType);
    if (error != null) {
      messenger?.showSnackBar(SnackBar(content: Text(error), backgroundColor: AppColors.statusOverdueText));
    }
  } catch (e) {
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(content: Text(apiClient.handleError(e).message), backgroundColor: AppColors.statusOverdueText),
    );
  }
}
