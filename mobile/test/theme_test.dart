import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:school_connect/core/theme/theme_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('selected theme mode is persisted', () async {
    SharedPreferences.setMockInitialValues({});
    final notifier = ThemeModeNotifier();
    await notifier.setMode(ThemeMode.dark);

    expect(notifier.state, ThemeMode.dark);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app_theme_mode'), 'dark');
  });
}
