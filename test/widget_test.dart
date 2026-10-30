import 'package:flutter_test/flutter_test.dart';

import 'package:aestheticy/main.dart';

void main() {
  testWidgets('AudioLabScreen shows app name and credit', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AestheticyApp());
    await tester.pumpAndSettle();

    // Verify the app name is displayed in the AppBar.
    expect(find.textContaining('Aestheticy'), findsOneWidget);

    // Verify the credit text is displayed.
    expect(find.text('by mido'), findsOneWidget);
  });
}
