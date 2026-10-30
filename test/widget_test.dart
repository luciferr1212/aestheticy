import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/main.dart';

void main() {
  testWidgets('HomeScreen shows app name and credit', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AestheticyApp());

    // Verify the app name is displayed.
    expect(find.text('Aestheticy'), findsOneWidget);

    // Verify the credit text is displayed.
    expect(find.text('by mido'), findsOneWidget);
  });
}
