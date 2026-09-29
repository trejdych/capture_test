# capture_test

A monorepo for recording Flutter widget test steps as PNG images and viewing them in a local HTML report.

## Packages

| Package | Purpose |
| --- | --- |
| `capture_test_core` | `captureTestWidgets`, standard Flutter `Finder` actions, image capture and JSONL manifests. |
| `capture_test_patrol` | `capturePatrolWidgetTest` and a `PatrolTester` subclass that captures Patrol actions. |
| `capture_test_report` | A Dart-only HTML report generator. |

Each package has its own `pubspec.yaml`. The Patrol package depends on the core package through a local path while this monorepo is under development.

## Flutter tests without Patrol

```dart
captureTestWidgets('counter', (tester) async {
  await tester.pumpWidget(const MyApp());
  await tester.tap(find.byKey(const ValueKey('increment')));
  await tester.capture('custom checkpoint');
});
```

Capture is off by default. Enable it for a Flutter test command with
`--dart-define=CAPTURE_TEST_MODE=always`, or use
`--dart-define=CAPTURE_TEST_MODE=reportOnError` to keep frames only for failed
tests. The supported modes are `off`, `always`, and `reportOnError`.

In Dart, set `globalCaptureMode = CaptureMode.always` before registering tests,
pass `CaptureOptions(mode: CaptureMode.always)` to one test, or change
`tester.captureMode` within a test. Per-test options take precedence over the
global mode. The same controls work with `capturePatrolWidgetTest`.

`CAPTURE_TEST_ONLY` filters test names. `CAPTURE_TEST_OUTPUT` selects the output
directory, and `CAPTURE_TEST_MAX_FRAMES` changes the default limit. Pass these
through `--dart-define`. In `reportOnError` mode, frames are held in a temporary
directory until the test finishes. Successful tests remove them. The default
output directory is `build/captures` relative to the directory where the test
command runs.

The callback receives a `CaptureTester` with a `raw` `WidgetTester` for operations outside the capture API. Calls made through `raw` are not automatically captured; call `capture()` after them when a frame is useful. `pumpWidget` records the initial frame. The action methods settle animations before recording. Input text is never written to the manifest.

Pass an optional `description` to actions such as
`tester.tap(finder, description: 'Open profile')` to show their purpose beside
the screenshot. Failed tests show the error type and source location. Error
messages and stack traces are not saved, since they can contain input values or
personal data.

## Patrol tests

```dart
capturePatrolWidgetTest('counter', ($) async {
  await $.pumpWidgetAndSettle(const MyApp());
  await $.tap(find.byKey(const ValueKey('increment')));
});
```

The callback receives a `PatrolTester` subclass, so functions expecting `PatrolTester` can receive it. `pumpWidgetAndSettle`, `tap`, `longPress`, `enterText`, and `dragUntilVisible` record frames. Direct calls to `$.tester` and actions on a `PatrolFinder` do not pass through these overrides; call `$.capture('description')` after those actions.
The Patrol wrapper accepts optional descriptions on `tap`, `longPress`,
`enterText`, `dragUntilVisible`, and `pumpWidgetAndSettle`. Recorded targets use
the matched widget type when one is available. Direct tester calls can use
`$.tap(finder, description: 'Open profile')`. Finder chains retain Patrol's API:
`$(ProfileButton).describedAs('Open profile').tap()`. Without `describedAs`,
`$(ProfileButton).tap()` continues to work and uses automatic target details.

## Report

Run from the Flutter project's root after a capture test:

```sh
dart run capture_test_report
```

The test run writes PNG frames and manifests. The command above generates one
`build/captures/report.html` combining every captured case and layout in the
output directory. Each captured case also writes its result to `result.json`.
The report groups variants of the same test under a picker, shows pass/fail
badges, provides test search, and scrolls the test list independently from the
screenshots. In `reportOnError` mode, only failed cases appear. Pass
`CaptureOptions(testGroup: 'test name')` to group variants with different test
descriptions; matching `[layout]` suffixes are also grouped automatically.
Its default input is `build/captures`; you can pass a different directory as the
first argument. Captures are capped at 60 distinct frames per test by default.
`CaptureOptions` controls the output directory, layout label, frame limit, and
image capture function.

The report is a viewer for test steps. It does not compare images with golden baselines. Capturing requires a test platform that supports `flutter_test` image capture; browser based Flutter tests do not support it.

## Development

Run `flutter pub get` and `flutter test` inside each Flutter package. Run `dart pub get`, `dart test`, and `dart run bin/capture_test_report.dart --help` inside `capture_test_report`.
