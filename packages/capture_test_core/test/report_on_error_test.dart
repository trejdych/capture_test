import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // Failure handling has to run in another process. This suite can then read
  // the files that captureTestWidgets keeps or deletes.
  test('reportOnError publishes failed tests and discards successful ones',
      () async {
    final output =
        Directory.systemTemp.createTempSync('capture_report_on_error_');
    addTearDown(() => output.deleteSync(recursive: true));
    final flutterRoot = Platform.environment['FLUTTER_ROOT'];
    final flutter =
        flutterRoot == null ? 'flutter' : '$flutterRoot/bin/flutter';
    final result = await Process.run(
      flutter,
      [
        'test',
        '--no-pub',
        '--reporter',
        'compact',
        '--dart-define=CAPTURE_TEST_MODE=reportOnError',
        '--dart-define=CAPTURE_TEST_OUTPUT=${output.path}',
        'test/fixtures/report_on_error_success.dart',
        'test/fixtures/report_on_error_failure.dart',
        'test/fixtures/report_on_error_framework.dart',
      ],
      workingDirectory: Directory.current.path,
    );
    expect(
      result.exitCode,
      isNonZero,
      reason: '${result.stdout}\n${result.stderr}',
    );
    expect(result.stdout, contains('+1 -2: Some tests failed.'));

    final saved = <String, String>{};
    for (final file in output.listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('result.json')) continue;
      final manifest = File('${file.parent.path}/manifest.jsonl');
      final frame =
          jsonDecode(manifest.readAsLinesSync().first) as Map<String, dynamic>;
      saved[frame['test'] as String] = file.readAsStringSync();
    }

    expect(
      saved.keys,
      unorderedEquals([
        'reports a failed assertion',
        'reports a framework error',
      ]),
    );
    final assertion = jsonDecode(saved['reports a failed assertion']!)
        as Map<String, dynamic>;
    expect(assertion['status'], 'failed');
    expect(assertion['errorType'], 'TestFailure');
    expect(
      assertion['location'],
      contains('report_on_error_failure.dart'),
    );
    expect(saved['reports a failed assertion'], isNot(contains('Expected:')));

    final framework =
        jsonDecode(saved['reports a framework error']!) as Map<String, dynamic>;
    expect(framework['status'], 'failed');
    expect(framework['errorType'], 'StateError');
    expect(
      framework['location'],
      contains('report_on_error_framework.dart'),
    );
    expect(saved['reports a framework error'], isNot(contains('build failed')));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
