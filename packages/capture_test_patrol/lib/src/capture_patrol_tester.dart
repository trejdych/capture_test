import 'package:capture_test_core/capture_test_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol_finders/patrol_finders.dart';

typedef CapturePatrolCallback = Future<void> Function(
    CapturePatrolTester tester);

void capturePatrolWidgetTest(
  String description,
  CapturePatrolCallback callback, {
  CaptureOptions options = const CaptureOptions(),
  bool? skip,
  Timeout? timeout,
  bool semanticsEnabled = true,
  TestVariant<Object?> variant = const DefaultTestVariant(),
  dynamic tags,
  PatrolTesterConfig config = const PatrolTesterConfig(),
}) {
  patrolWidgetTest(
    description,
    (tester) async {
      final session = CaptureSession(
        name: tester.tester.testDescription,
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
        await callback(CapturePatrolTester(tester, session));
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
    config: config,
  );
}

class CapturePatrolTester extends PatrolTester {
  CapturePatrolTester(PatrolTester inner, this.session)
      : super(tester: inner.tester, config: inner.config);

  final CaptureSession session;

  CaptureMode get captureMode => session.mode;

  set captureMode(CaptureMode value) => session.mode = value;

  Future<void> capture(String action,
          {String? target, String? screen, String? description}) =>
      session.record(tester,
          action: action,
          target: target,
          screen: screen,
          description: description);

  @override
  Future<void> pumpWidgetAndSettle(
    Widget widget, {
    Duration? duration,
    EnginePhase phase = EnginePhase.sendSemanticsUpdate,
    Duration? timeout,
    String? description,
  }) async {
    await super.pumpWidgetAndSettle(
      widget,
      duration: duration,
      phase: phase,
      timeout: timeout,
    );
    await capture('start', description: description);
  }

  @override
  Future<void> tap(
    Finder finder, {
    SettlePolicy? settlePolicy,
    Duration? visibleTimeout,
    Duration? settleTimeout,
    Alignment alignment = Alignment.center,
    bool enablePatrolLog = true,
    String? description,
  }) async {
    final target = _target(finder);
    final actionDescription = _description(finder, description);
    await super.tap(
      finder,
      settlePolicy: settlePolicy,
      visibleTimeout: visibleTimeout,
      settleTimeout: settleTimeout,
      alignment: alignment,
      enablePatrolLog: enablePatrolLog,
    );
    await capture('tap', target: target, description: actionDescription);
  }

  @override
  Future<void> longPress(
    Finder finder, {
    SettlePolicy? settlePolicy,
    Duration? visibleTimeout,
    Duration? settleTimeout,
    Alignment alignment = Alignment.center,
    bool enablePatrolLog = true,
    String? description,
  }) async {
    final target = _target(finder);
    final actionDescription = _description(finder, description);
    await super.longPress(
      finder,
      settlePolicy: settlePolicy,
      visibleTimeout: visibleTimeout,
      settleTimeout: settleTimeout,
      alignment: alignment,
      enablePatrolLog: enablePatrolLog,
    );
    await capture('longPress', target: target, description: actionDescription);
  }

  @override
  Future<void> enterText(
    Finder finder,
    String text, {
    SettlePolicy? settlePolicy,
    Duration? visibleTimeout,
    Duration? settleTimeout,
    Alignment alignment = Alignment.center,
    bool enablePatrolLog = true,
    bool hideKeyboard = true,
    String? description,
  }) async {
    final target = _target(finder);
    final actionDescription = _description(finder, description);
    await super.enterText(
      finder,
      text,
      settlePolicy: settlePolicy,
      visibleTimeout: visibleTimeout,
      settleTimeout: settleTimeout,
      alignment: alignment,
      enablePatrolLog: enablePatrolLog,
      hideKeyboard: hideKeyboard,
    );
    await capture('enterText', target: target, description: actionDescription);
  }

  @override
  Future<PatrolFinder> dragUntilVisible({
    required Finder finder,
    required Finder view,
    required Offset moveStep,
    int maxIteration = defaultScrollMaxIteration,
    Duration? settleBetweenScrollsTimeout,
    Duration? dragDuration,
    SettlePolicy? settlePolicy,
    Alignment alignment = Alignment.center,
    bool enablePatrolLog = true,
    String? description,
  }) async {
    final result = await super.dragUntilVisible(
      finder: finder,
      view: view,
      moveStep: moveStep,
      maxIteration: maxIteration,
      settleBetweenScrollsTimeout: settleBetweenScrollsTimeout,
      dragDuration: dragDuration,
      settlePolicy: settlePolicy,
      alignment: alignment,
      enablePatrolLog: enablePatrolLog,
    );
    await capture('scrollTo',
        target: _target(finder),
        description: _description(finder, description));
    return result;
  }
}

final _finderDescriptions = Expando<String>();

extension CapturePatrolFinderDescription on PatrolFinder {
  PatrolFinder describedAs(String description) {
    _finderDescriptions[this] = description;
    return this;
  }
}

String? _description(Finder finder, String? explicit) =>
    explicit ?? _finderDescriptions[finder];

String _target(Finder finder) {
  final elements = finder.evaluate();
  if (elements.isNotEmpty) return elements.first.widget.runtimeType.toString();
  return finder.runtimeType.toString();
}
