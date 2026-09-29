import 'package:capture_test_core/capture_test_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Invoked by test/report_on_error_test.dart. The name is not *_test.dart, so a
// normal `flutter test` run does not collect it on its own.
void main() {
  captureTestWidgets('discards a successful test', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Text('success')));
    expect(find.text('success'), findsOneWidget);
  });
}
