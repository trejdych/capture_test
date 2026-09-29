import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:capture_test_core/capture_test_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final wrapperOutput = Directory.systemTemp.createTempSync('capture_wrapper_');
  tearDown(() {
    if (wrapperOutput.existsSync()) {
      wrapperOutput.deleteSync(recursive: true);
    }
  });

  testWidgets('captures normal Finder actions and writes separate JSONL lines',
      (raw) async {
    final output = Directory.systemTemp.createTempSync('capture_core_test_');
    addTearDown(() => output.deleteSync(recursive: true));
    final session = CaptureSession(
      name: 'counter',
      options: CaptureOptions(
        outputDirectory: output.path,
        layout: 'phone',
        mode: CaptureMode.always,
        screenName: (_) => 'CounterScreen',
      ),
    );
    final tester = CaptureTester(raw, session);

    await tester.pumpWidget(const MaterialApp(home: _Counter()));
    await tester.tap(
      find.byKey(const ValueKey('increment')),
      description: 'Increment counter',
    );
    expect(find.text('1'), findsOneWidget);

    final manifest = File('${session.directory.path}/manifest.jsonl');
    final lines = manifest.readAsLinesSync();
    expect(lines, hasLength(2));
    expect(jsonDecode(lines.first)['action'], 'start');
    expect(jsonDecode(lines.first)['screen'], 'CounterScreen');
    expect(jsonDecode(lines.last)['action'], 'tap');
    expect(jsonDecode(lines.last)['description'], 'Increment counter');
    expect(
        File('${session.directory.parent.parent.path}/${jsonDecode(lines.last)['file']}')
            .existsSync(),
        isTrue);
    session.finish(failed: false);
    expect(
      jsonDecode(File('${session.directory.path}/result.json')
          .readAsStringSync())['status'],
      'passed',
    );
  });

  captureTestWidgets(
    'wrapper records the test name',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Text('ready')));
      final frame = jsonDecode(
        File('${tester.session.directory.path}/manifest.jsonl')
            .readAsLinesSync()
            .single,
      ) as Map<String, dynamic>;
      expect(frame['test'], 'wrapper records the test name');
      expect(frame['action'], 'start');
    },
    options: CaptureOptions(
      outputDirectory: wrapperOutput.path,
      mode: CaptureMode.always,
    ),
  );

  test('capture mode accepts the supported values', () {
    expect(CaptureMode.parse('off'), CaptureMode.off);
    expect(CaptureMode.parse('always'), CaptureMode.always);
    expect(CaptureMode.parse('reportOnError'), CaptureMode.reportOnError);
    expect(() => CaptureMode.parse('invalid'), throwsFormatException);
  });

  test('session mode uses the global default unless the test overrides it', () {
    final previous = globalCaptureMode;
    globalCaptureMode = CaptureMode.always;
    try {
      expect(CaptureSession(name: 'mode').mode, CaptureMode.always);
      expect(
        CaptureSession(
          name: 'mode',
          options: const CaptureOptions(mode: CaptureMode.off),
        ).mode,
        CaptureMode.off,
      );
    } finally {
      globalCaptureMode = previous;
    }
  });

  testWidgets('capture mode can change inside a test', (raw) async {
    final output = Directory.systemTemp.createTempSync('capture_mode_test_');
    addTearDown(() => output.deleteSync(recursive: true));
    var captures = 0;
    final session = CaptureSession(
      name: 'changed mode',
      options: CaptureOptions(
        outputDirectory: output.path,
        imageCapture: (_) async {
          captures += 1;
          return _solidImage(captures);
        },
      ),
    );
    final tester = CaptureTester(raw, session);
    expect(tester.captureMode, CaptureMode.off);
    await tester.pumpWidget(const MaterialApp(home: Text('ready')));
    expect(find.text('ready'), findsOneWidget);
    expect(captures, 0);
    expect(output.listSync(), isEmpty);
    tester.captureMode = CaptureMode.always;
    await tester.capture('after enabling');
    expect(captures, 1);
    expect(_actions(session), ['after enabling']);
  });

  testWidgets('reportOnError discards frames after a successful test',
      (raw) async {
    final output = Directory.systemTemp.createTempSync('capture_success_');
    addTearDown(() => output.deleteSync(recursive: true));
    var captures = 0;
    final session = CaptureSession(
      name: 'success',
      options: CaptureOptions(
        outputDirectory: output.path,
        mode: CaptureMode.reportOnError,
        imageCapture: (_) async {
          captures += 1;
          return _solidImage(captures);
        },
      ),
    );
    await CaptureTester(raw, session).pumpWidget(const SizedBox.shrink());
    expect(captures, 1);
    expect(output.listSync(), isEmpty);
    session.finish(failed: false);
    expect(output.listSync(), isEmpty);
  });

  testWidgets('switching reportOnError to always publishes the pending frame',
      (raw) async {
    final output = Directory.systemTemp.createTempSync('capture_promote_');
    addTearDown(() => output.deleteSync(recursive: true));
    var captures = 0;
    final session = CaptureSession(
      name: 'promote',
      options: CaptureOptions(
        outputDirectory: output.path,
        mode: CaptureMode.reportOnError,
        imageCapture: (_) async {
          captures += 1;
          return _solidImage(captures);
        },
      ),
    );
    final tester = CaptureTester(raw, session);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(captures, 1);
    expect(session.directory.existsSync(), isFalse);
    tester.captureMode = CaptureMode.always;
    expect(captures, 1);
    expect(_actions(session), ['start']);
  });

  testWidgets('reportOnError publishes frames after a failure', (raw) async {
    final output = Directory.systemTemp.createTempSync('capture_failure_');
    addTearDown(() => output.deleteSync(recursive: true));
    final session = CaptureSession(
      name: 'failure',
      options: CaptureOptions(
        outputDirectory: output.path,
        mode: CaptureMode.reportOnError,
      ),
    );
    await CaptureTester(raw, session).pumpWidget(
      const MaterialApp(home: Text('ready')),
    );
    expect(session.directory.existsSync(), isFalse);
    session.finish(failed: true);
    expect(
        File('${session.directory.path}/manifest.jsonl').existsSync(), isTrue);
    expect(
      jsonDecode(File('${session.directory.path}/result.json')
          .readAsStringSync())['status'],
      'failed',
    );
  });

  testWidgets('records the failing source location', (raw) async {
    final output = Directory.systemTemp.createTempSync('capture_step_failure_');
    addTearDown(() => output.deleteSync(recursive: true));
    final session = CaptureSession(
      name: 'step failure',
      options: CaptureOptions(
        outputDirectory: output.path,
        mode: CaptureMode.reportOnError,
      ),
    );
    final tester = CaptureTester(raw, session);
    await tester.pumpWidget(const MaterialApp(home: Text('ready')));
    const secret = 'user-secret-error';
    session.recordFailure(StateError(secret), StackTrace.current);
    session.finish(failed: true);
    final resultFile = File('${session.directory.path}/result.json');
    final result =
        jsonDecode(resultFile.readAsStringSync()) as Map<String, dynamic>;
    expect(result['errorType'], 'StateError');
    expect(result['location'], contains('capture_tester_test.dart:'));
    expect(resultFile.readAsStringSync(), isNot(contains(secret)));
  });

  testWidgets('records each finder action in the manifest', (raw) async {
    final output = Directory.systemTemp.createTempSync('capture_actions_');
    addTearDown(() => output.deleteSync(recursive: true));
    var seed = 0;
    final session = CaptureSession(
      name: 'actions',
      options: CaptureOptions(
        outputDirectory: output.path,
        mode: CaptureMode.always,
        imageCapture: (_) async => _solidImage(++seed),
      ),
    );
    final tester = CaptureTester(raw, session);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GestureDetector(
            key: const ValueKey('box'),
            behavior: HitTestBehavior.opaque,
            onLongPress: () {},
            child: const ColoredBox(
              color: Colors.red,
              child: SizedBox(width: 80, height: 80),
            ),
          ),
        ),
      ),
    );
    await tester.longPress(find.byKey(const ValueKey('box')));
    await tester.drag(find.byKey(const ValueKey('box')), const Offset(0, -20));
    await tester.pumpAndSettle();
    await tester.capture('checkpoint');
    expect(
      _actions(session),
      ['start', 'longPress', 'drag', 'settle', 'checkpoint'],
    );
  });

  testWidgets('omits entered text from the manifest', (raw) async {
    final output = Directory.systemTemp.createTempSync('capture_text_');
    addTearDown(() => output.deleteSync(recursive: true));
    final session = CaptureSession(
      name: 'text',
      options: CaptureOptions(
        outputDirectory: output.path,
        mode: CaptureMode.always,
      ),
    );
    final tester = CaptureTester(raw, session);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: TextField(key: ValueKey('field'))),
      ),
    );
    const secret = 'secret-input-value';
    await tester.enterText(find.byKey(const ValueKey('field')), secret);
    expect(find.text(secret), findsOneWidget);
    final manifest =
        File('${session.directory.path}/manifest.jsonl').readAsStringSync();
    expect(manifest, isNot(contains(secret)));
    expect(_actions(session), contains('enterText'));
  }, timeout: const Timeout(Duration(seconds: 20)));

  testWidgets('skips a frame identical to the previous one', (raw) async {
    final output = Directory.systemTemp.createTempSync('capture_dedup_');
    addTearDown(() => output.deleteSync(recursive: true));
    final session = CaptureSession(
      name: 'dedup',
      options: CaptureOptions(
        outputDirectory: output.path,
        mode: CaptureMode.always,
        imageCapture: (_) => _solidImage(1),
      ),
    );
    final tester = CaptureTester(raw, session);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.capture('again');
    expect(_actions(session), ['start']);
  });

  testWidgets('stops recording at the frame limit', (raw) async {
    final output = Directory.systemTemp.createTempSync('capture_limit_');
    addTearDown(() => output.deleteSync(recursive: true));
    var seed = 0;
    final session = CaptureSession(
      name: 'limit',
      options: CaptureOptions(
        outputDirectory: output.path,
        mode: CaptureMode.always,
        maxFrames: 1,
        imageCapture: (_) async => _solidImage(++seed),
      ),
    );
    final tester = CaptureTester(raw, session);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.capture('extra');
    expect(_actions(session), ['start']);
  });
}

List<String> _actions(CaptureSession session) {
  return File('${session.directory.path}/manifest.jsonl')
      .readAsLinesSync()
      .where((line) => line.trim().isNotEmpty)
      .map((line) =>
          (jsonDecode(line) as Map<String, dynamic>)['action'] as String)
      .toList();
}

Future<ui.Image> _solidImage(int seed) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, 4, 4),
    ui.Paint()..color = ui.Color.fromARGB(255, seed & 255, 32, 64),
  );
  return recorder.endRecording().toImage(4, 4);
}

class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int count = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(
          children: [
            Container(
                width: 40,
                height: 40,
                color: count == 0 ? Colors.red : Colors.blue),
            Text('$count'),
            TextButton(
              key: const ValueKey('increment'),
              onPressed: () => setState(() => count++),
              child: const Text('Increment'),
            ),
          ],
        ),
      );
}
