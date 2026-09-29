import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:test_api/src/backend/invoker.dart';

import 'capture_mode.dart';

typedef CaptureImage = Future<ui.Image> Function(WidgetTester tester);

class CaptureOptions {
  const CaptureOptions({
    this.outputDirectory = const String.fromEnvironment(
      'CAPTURE_TEST_OUTPUT',
      defaultValue: 'build/captures',
    ),
    this.maxFrames = const int.fromEnvironment(
      'CAPTURE_TEST_MAX_FRAMES',
      defaultValue: 60,
    ),
    this.layout = 'default',
    this.testGroup,
    this.mode,
    this.imageCapture,
    this.screenName,
  });

  final String outputDirectory;
  final int maxFrames;
  final String layout;
  final String? testGroup;
  final CaptureMode? mode;
  final CaptureImage? imageCapture;
  final String? Function(WidgetTester tester)? screenName;
}

class CaptureSession {
  CaptureSession({required this.name, this.options = const CaptureOptions()})
      : _mode = modeForTest(name, options.mode);

  final String name;
  final CaptureOptions options;
  CaptureMode _mode;
  int _nextIndex = 0;
  int? _lastDigest;
  bool _prepared = false;
  bool _published = false;
  bool _finalized = false;
  String? _errorType;
  String? _errorLocation;
  Directory? _pendingDirectory;
  final _pendingManifest = <String>[];

  CaptureMode get mode => _mode;

  set mode(CaptureMode value) {
    if (_mode == CaptureMode.reportOnError && value == CaptureMode.always) {
      _publishPending();
    }
    _mode = value;
  }

  String get _flowDirectory =>
      '${_slug(name)}_${_hash(utf8.encode(name)).toRadixString(16)}';

  String get _layoutDirectory => _slug(options.layout);

  Directory get directory => Directory(
        '${options.outputDirectory}/$_flowDirectory/$_layoutDirectory',
      );

  void recordFailure(Object error, StackTrace stackTrace) {
    _errorType ??= error.runtimeType.toString();
    _errorLocation ??= _sourceLocation(stackTrace);
  }

  void monitorTestOutcome() {
    final liveTest = Invoker.current?.liveTest;
    if (liveTest == null) {
      throw StateError('CaptureSession must run inside a test.');
    }
    liveTest.onError.listen((error) {
      _errorType ??= error.error is String
          ? 'Test failure'
          : error.error.runtimeType.toString();
      _errorLocation ??= _sourceLocation(error.stackTrace);
    });
    addTearDown(() => finish(failed: liveTest.state.result.isFailing));
    liveTest.onComplete.then(
      (_) => finish(failed: liveTest.state.result.isFailing),
    );
  }

  void finish({required bool failed}) {
    if (_finalized) return;
    if (failed) {
      _publishPending();
    } else {
      _discardPending();
    }
    if (_prepared) {
      File('${directory.path}/result.json').writeAsStringSync(
        jsonEncode({
          'status': failed ? 'failed' : 'passed',
          if (failed && _errorType != null) 'errorType': _errorType,
          if (failed && _errorLocation != null) 'location': _errorLocation,
        }),
      );
    }
    _finalized = true;
  }

  Future<void> record(
    WidgetTester tester, {
    required String action,
    String? target,
    String? screen,
    String? description,
  }) async {
    if (_mode == CaptureMode.off ||
        _finalized ||
        _nextIndex >= options.maxFrames) {
      return;
    }
    if (!canCaptureImage && options.imageCapture == null) {
      throw UnsupportedError(
          'Image capture is unavailable on this test platform.');
    }
    final bytes = await tester.runAsync(() async {
      final image =
          await (options.imageCapture?.call(tester) ?? _captureRoot(tester));
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) throw StateError('Could not encode capture as PNG.');
        return data.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    });
    if (bytes == null) throw StateError('Image capture did not complete.');
    final digest = _hash(bytes);
    if (digest == _lastDigest) return;
    _lastDigest = digest;
    final index = _nextIndex++;
    final fileName = '${index.toString().padLeft(3, '0')}_${_slug(action)}.png';
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    final manifestLine = '${jsonEncode({
          'schemaVersion': 1,
          'test': name,
          'testGroup': options.testGroup,
          'layout': options.layout,
          'width': size.width.round(),
          'height': size.height.round(),
          'index': index,
          'screen': screen ?? options.screenName?.call(tester),
          'action': action,
          'description': description,
          'target': target,
          'file': '$_flowDirectory/$_layoutDirectory/$fileName',
        })}\n';

    if (_mode == CaptureMode.reportOnError && !_published) {
      final pending = _pendingDirectory ??=
          Directory.systemTemp.createTempSync('capture_test_');
      File('${pending.path}/$fileName').writeAsBytesSync(bytes);
      _pendingManifest.add(manifestLine);
      return;
    }
    _prepareOutput();
    File('${directory.path}/$fileName').writeAsBytesSync(bytes);
    File('${directory.path}/manifest.jsonl').writeAsStringSync(
      manifestLine,
      mode: FileMode.append,
    );
  }

  void _prepareOutput() {
    if (_prepared) return;
    final output = directory;
    if (output.existsSync()) output.deleteSync(recursive: true);
    output.createSync(recursive: true);
    _prepared = true;
  }

  void _publishPending() {
    final pending = _pendingDirectory;
    if (pending == null) return;
    _prepareOutput();
    for (final file in pending.listSync().whereType<File>()) {
      file.copySync('${directory.path}/${file.uri.pathSegments.last}');
    }
    File('${directory.path}/manifest.jsonl').writeAsStringSync(
      _pendingManifest.join(),
      mode: FileMode.append,
    );
    _discardPending();
    _published = true;
  }

  void _discardPending() {
    final pending = _pendingDirectory;
    if (pending != null && pending.existsSync()) {
      pending.deleteSync(recursive: true);
    }
    _pendingDirectory = null;
    _pendingManifest.clear();
  }
}

String? _sourceLocation(StackTrace? stackTrace) {
  final text = stackTrace?.toString() ?? '';
  final local = RegExp(r'file:///[^\s()]*?/(test/[^\s():]+\.dart:\d+:\d+)')
      .firstMatch(text);
  if (local != null) return local.group(1);
  return RegExp(r'(test/[^\s():]+\.dart:\d+:\d+)').firstMatch(text)?.group(1);
}

Future<ui.Image> _captureRoot(WidgetTester tester) async {
  final element = tester.binding.rootElement;
  if (element == null) throw StateError('Pump a widget before capturing.');
  return captureImage(element);
}

String _slug(String value) {
  final slug = value.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '_');
  final trimmed = slug.replaceAll(RegExp(r'^_+|_+$'), '');
  return trimmed.isEmpty ? 'capture' : trimmed;
}

int _hash(List<int> bytes) {
  var hash = 0x811c9dc5;
  for (final byte in bytes) {
    hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
  }
  return hash;
}
