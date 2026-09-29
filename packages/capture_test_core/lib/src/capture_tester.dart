import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'capture_session.dart';
import 'capture_mode.dart';

typedef CaptureWidgetTestCallback = Future<void> Function(CaptureTester tester);

void captureTestWidgets(
  String description,
  CaptureWidgetTestCallback callback, {
  CaptureOptions options = const CaptureOptions(),
  bool? skip,
  Timeout? timeout,
  bool semanticsEnabled = true,
  TestVariant<Object?> variant = const DefaultTestVariant(),
  dynamic tags,
  int? retry,
}) {
  testWidgets(
    description,
    (tester) async {
      final session = CaptureSession(
        name: tester.testDescription,
        options: options,
      )..monitorTestOutcome();
      final previousOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        session.recordFailure(
          details.exception,
          details.stack ?? StackTrace.empty,
        );
        previousOnError?.call(details);
      };
      try {
        await callback(CaptureTester(tester, session));
      } catch (error, stackTrace) {
        session.recordFailure(error, stackTrace);
        rethrow;
      } finally {
        FlutterError.onError = previousOnError;
      }
    },
    skip: skip,
    timeout: timeout,
    semanticsEnabled: semanticsEnabled,
    variant: variant,
    tags: tags,
    retry: retry,
  );
}

class CaptureTester {
  CaptureTester(this.raw, this.session);

  final WidgetTester raw;
  final CaptureSession session;

  CaptureMode get captureMode => session.mode;

  set captureMode(CaptureMode value) => session.mode = value;

  Future<void> pumpWidget(Widget widget, {String? description}) async {
    await raw.pumpWidget(widget);
    await session.record(raw, action: 'start', description: description);
  }

  Future<void> tap(Finder finder, {String? label, String? description}) async {
    await raw.tap(finder);
    await raw.pumpAndSettle();
    await session.record(raw,
        action: 'tap',
        target: label ?? _target(finder),
        description: description);
  }

  Future<void> longPress(Finder finder,
      {String? label, String? description}) async {
    await raw.longPress(finder);
    await raw.pumpAndSettle();
    await session.record(raw,
        action: 'longPress',
        target: label ?? _target(finder),
        description: description);
  }

  Future<void> enterText(Finder finder, String value,
      {String? label, String? description}) async {
    await raw.enterText(finder, value);
    await raw.pumpAndSettle();
    await session.record(raw,
        action: 'enterText',
        target: label ?? _target(finder),
        description: description);
  }

  Future<void> drag(Finder finder, Offset offset,
      {String? label, String? description}) async {
    await raw.drag(finder, offset);
    await raw.pumpAndSettle();
    await session.record(raw,
        action: 'drag',
        target: label ?? _target(finder),
        description: description);
  }

  Future<void> pumpAndSettle({String? description}) async {
    await raw.pumpAndSettle();
    await session.record(raw, action: 'settle', description: description);
  }

  Future<void> capture(String action,
          {String? target, String? screen, String? description}) =>
      session.record(raw,
          action: action,
          target: target,
          screen: screen,
          description: description);
}

String _target(Finder finder) => finder.runtimeType.toString();
