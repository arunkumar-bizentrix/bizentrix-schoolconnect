import 'dart:io';

import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

/// Android / iOS: write to the app's temporary folder and hand the file to
/// whatever app opens that type. Returns an error message, or null.
Future<String?> saveAndOpen(List<int> bytes, String fileName, String mimeType) async {
  final directory = await getTemporaryDirectory();
  final safeName = fileName.replaceAll(RegExp(r'[\/:*?"<>|]'), '_');
  final file = File('${directory.path}${Platform.pathSeparator}$safeName');
  await file.writeAsBytes(bytes, flush: true);

  final result = await OpenFilex.open(file.path, type: mimeType.split(';').first);
  if (result.type == ResultType.done) return null;
  if (result.type == ResultType.noAppToOpen) {
    return 'No app on this phone can open this file type.';
  }
  return 'Could not open the file: ${result.message}';
}
