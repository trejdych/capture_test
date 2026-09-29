import 'dart:convert';
import 'dart:io';

import 'package:capture_test_report/capture_test_report.dart';
import 'package:test/test.dart';

void main() {
  test('loads JSONL frames and escapes report content', () {
    final root = Directory.systemTemp.createTempSync('capture_report_test_');
    addTearDown(() => root.deleteSync(recursive: true));
    final flow = Directory('${root.path}/flow/phone')
      ..createSync(recursive: true);
    final manifest = File('${flow.path}/manifest.jsonl');
    manifest.writeAsStringSync([
      {
        'schemaVersion': 1,
        'test': '<script>alert(1)</script>',
        'layout': 'phone',
        'index': 0,
        'action': 'start',
        'target': null,
        'screen': null,
        'file': 'flow/phone/000_start.png',
        'width': 430,
        'height': 844
      },
      {
        'schemaVersion': 1,
        'test': '<script>alert(1)</script>',
        'layout': 'phone',
        'index': 1,
        'action': 'tap',
        'target': 'button',
        'screen': null,
        'file': 'flow/phone/001_tap.png',
        'width': 430,
        'height': 844
      },
    ].map(jsonEncode).join('\n'));
    File('${flow.path}/result.json').writeAsStringSync('{"status":"passed"}');

    final frames = loadFrames(root);
    expect(frames, hasLength(2));
    expect(frames.first.status, CaptureStatus.passed);
    final html = renderReport(frames);
    expect(html, contains('&lt;script&gt;alert(1)&lt;/script&gt;'));
    expect(html, isNot(contains('<script>alert(1)</script>')));
    expect(html, contains('flow/phone/001_tap.png'));
  });

  test('groups variants under one test with status badges', () {
    final phone = CaptureFrame.fromJson({
      'schemaVersion': 1,
      'test': 'login [phone]',
      'testGroup': 'login',
      'layout': 'phone',
      'index': 0,
      'action': 'start',
      'file': 'phone.png',
      'width': 430,
      'height': 844,
    }, status: CaptureStatus.passed);
    final desktop = CaptureFrame.fromJson({
      'schemaVersion': 1,
      'test': 'login [desktop]',
      'testGroup': 'login',
      'layout': 'desktop',
      'index': 0,
      'action': 'start',
      'file': 'desktop.png',
      'width': 1440,
      'height': 900,
    }, status: CaptureStatus.failed);

    final html = renderReport([phone, desktop]);
    expect('class="flow-button"'.allMatches(html), hasLength(1));
    expect('data-flow="login"'.allMatches(html), hasLength(3));
    expect(html, contains('data-layout="phone" data-status="passed"'));
    expect(html, contains('data-layout="desktop" data-status="failed"'));
    expect(html, contains('<span class="badge failed">Failed</span>'));
  });

  test('derives a test group from the layout suffix', () {
    expect(_frame(test: 'login [phone]', layout: 'phone').testGroup, 'login');
    expect(
      _frame(test: 'login [desktop]', layout: 'desktop').testGroup,
      'login',
    );
    expect(_frame(test: 'checkout', layout: 'phone').testGroup, 'checkout');
    expect(
      _frame(test: 'login [phone]', layout: 'phone', testGroup: 'auth')
          .testGroup,
      'auth',
    );
    expect(
      _frame(test: 'login [phone]', layout: 'phone', testGroup: '').testGroup,
      'login',
    );
  });

  test('rejects an unsupported capture schema', () {
    expect(
      () => CaptureFrame.fromJson({'schemaVersion': 2}),
      throwsFormatException,
    );
  });

  test('shows failure location and action descriptions', () {
    final root = Directory.systemTemp.createTempSync('capture_failure_report_');
    addTearDown(() => root.deleteSync(recursive: true));
    final flow = Directory('${root.path}/flow/phone')
      ..createSync(recursive: true);
    File('${flow.path}/manifest.jsonl').writeAsStringSync('${jsonEncode({
          'schemaVersion': 1,
          'test': 'login [phone]',
          'layout': 'phone',
          'index': 0,
          'action': 'tap',
          'description': 'Open profile',
          'target': 'Button',
          'file': 'flow/phone/000_tap.png',
          'width': 430,
          'height': 844,
        })}\n');
    File('${flow.path}/result.json').writeAsStringSync(jsonEncode({
      'status': 'failed',
      'errorType': 'TestFailure',
      'location': 'test/login_test.dart:42:7',
    }));

    final html = renderReport(loadFrames(root));
    expect(html, contains('Open profile'));
    expect(html, contains('TestFailure'));
    expect(html, contains('test/login_test.dart:42:7'));
    expect(html, contains('tap · Button'));
  });

  test('CLI writes an HTML report from a manifest', () async {
    final root = Directory.systemTemp.createTempSync('capture_report_cli_');
    addTearDown(() => root.deleteSync(recursive: true));
    final flow = Directory('${root.path}/flow/phone')
      ..createSync(recursive: true);
    File('${flow.path}/manifest.jsonl').writeAsStringSync('${jsonEncode({
          'schemaVersion': 1,
          'test': 'sample',
          'layout': 'phone',
          'index': 0,
          'action': 'start',
          'target': null,
          'screen': null,
          'file': 'flow/phone/000_start.png',
          'width': 430,
          'height': 844,
        })}\n');

    final result = await _runReport([root.path]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    final report = File('${root.path}/report.html');
    expect(report.readAsStringSync(), contains('sample'));
  });

  test('CLI prints usage for help flags', () async {
    for (final flag in ['--help', '-h']) {
      final result = await _runReport([flag]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(result.stdout, contains('capture-directory'));
    }
  });

  test('CLI rejects more than one directory', () async {
    final result = await _runReport(['build/captures', 'other']);
    expect(result.exitCode, 64, reason: '${result.stdout}\n${result.stderr}');
  });

  test('CLI rejects a directory without manifests', () async {
    final root = Directory.systemTemp.createTempSync('capture_report_empty_');
    addTearDown(() => root.deleteSync(recursive: true));
    final result = await _runReport([root.path]);
    expect(result.exitCode, 1, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stderr, contains('No capture manifests'));
    expect(File('${root.path}/report.html').existsSync(), isFalse);
  });
}

CaptureFrame _frame({
  required String test,
  required String layout,
  String? testGroup,
}) {
  return CaptureFrame.fromJson({
    'schemaVersion': 1,
    'test': test,
    'layout': layout,
    'index': 0,
    'action': 'start',
    'file': 'frame.png',
    'width': 430,
    'height': 844,
    if (testGroup != null) 'testGroup': testGroup,
  });
}

Future<ProcessResult> _runReport(List<String> arguments) {
  return Process.run(
    Platform.resolvedExecutable,
    ['run', 'bin/capture_test_report.dart', ...arguments],
  );
}
