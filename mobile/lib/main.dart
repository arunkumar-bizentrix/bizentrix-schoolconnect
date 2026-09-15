import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'core/push/push_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set system UI overlay style (status bar icon brightness)
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  // Push is optional: this returns false (and the app runs normally) until a
  // Firebase config is added.
  await PushService.initialise();

  runApp(
    const ProviderScope(
      child: SchoolConnectApp(),
    ),
  );
}
