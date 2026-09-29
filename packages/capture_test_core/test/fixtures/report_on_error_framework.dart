import 'package:capture_test_core/capture_test_core.dart';
import 'package:flutter/material.dart';

// Invoked by test/report_on_error_test.dart. The name is not *_test.dart, so a
// normal `flutter test` run does not collect it on its own.
void main() {
  captureTestWidgets('reports a framework error', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Text('ready')));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(builder: (_) => throw StateError('build failed')),
      ),
    );
  });
}
