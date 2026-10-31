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

  testWidgets('AudioInitErrorApp displays error message and copy button', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const AudioInitErrorApp(
        error: 'Test initialization error message',
        stackTrace: 'Test stack trace details',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Audio Engine Initialization Failed'), findsOneWidget);
    expect(find.textContaining('Test initialization error message'), findsOneWidget);
    expect(find.text('Copy Error Log'), findsOneWidget);
  });

  testWidgets('LibraryInitErrorApp displays error message and copy button', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const LibraryInitErrorApp(
        error: 'Database lock or corrupted file',
        stackTrace: 'SqliteException(5): database is locked',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Library database failed to open'), findsOneWidget);
    expect(find.textContaining('Database lock or corrupted file'), findsOneWidget);
    expect(find.text('Copy Error Log'), findsOneWidget);
  });
}
