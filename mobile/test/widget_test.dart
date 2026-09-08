import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:school_connect/app.dart';

void main() {
  testWidgets('SchoolConnectApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: SchoolConnectApp(),
      ),
    );
    expect(find.byType(SchoolConnectApp), findsOneWidget);
  });
}
