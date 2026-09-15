import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Web: turn the downloaded bytes into a local blob URL and open it in a new
/// tab (PDFs and images display; other types download). The blob URL only
/// exists in this browser session, so nothing shareable is created.
Future<String?> saveAndOpen(List<int> bytes, String fileName, String mimeType) async {
  final blob = web.Blob(
    [Uint8List.fromList(bytes).toJS].toJS,
    web.BlobPropertyBag(type: mimeType.split(';').first),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..target = '_blank'
    ..download = mimeType.contains('pdf') || mimeType.startsWith('image/') ? '' : fileName;
  anchor.click();
  Future<void>.delayed(const Duration(minutes: 1), () => web.URL.revokeObjectURL(url));
  return null;
}
