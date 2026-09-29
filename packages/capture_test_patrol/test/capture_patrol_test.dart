import 'dart:convert';
import 'dart:io';

import 'package:capture_test_core/capture_test_core.dart';
import 'package:capture_test_patrol/capture_test_patrol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  capturePatrolWidgetTest('captures Patrol actions', ($) async {
    var count = 0;
    await $.pumpWidgetAndSettle(MaterialApp(
      home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
                body: TextButton(
                  key: const ValueKey('increment'),
                  onPressed: () => setState(() => count++),
                  child: Column(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        color: count.isEven ? Colors.red : Colors.blue,
                      ),
                      Text('$count'),
                    ],
                  ),
                ),
              )),
    ));
    await $(find.byKey(const ValueKey('increment')))
        .describedAs('Increment counter')
        .tap();
    expect($(find.text('1')).exists, isTrue);
    final lines =
        File('${$.session.directory.path}/manifest.jsonl').readAsLinesSync();
    final firstTap = jsonDecode(lines.last) as Map<String, dynamic>;
    expect(firstTap['description'], 'Increment counter');
    expect(firstTap['action'], 'tap');
    expect(firstTap['target'], 'TextButton');
    await $.tap(
      find.byKey(const ValueKey('increment')),
      description: 'Increment counter again',
    );
    final updatedLines =
        File('${$.session.directory.path}/manifest.jsonl').readAsLinesSync();
    final secondTap = jsonDecode(updatedLines.last) as Map<String, dynamic>;
    expect(secondTap['description'], 'Increment counter again');
    expect(secondTap['target'], 'TextButton');

    await $.tester.tap(find.byKey(const ValueKey('increment')));
    await $.tester.pumpAndSettle();
    final afterDirect =
        File('${$.session.directory.path}/manifest.jsonl').readAsLinesSync();
    expect(afterDirect, hasLength(updatedLines.length));
    await $.capture('manual checkpoint');
    final afterManual =
        File('${$.session.directory.path}/manifest.jsonl').readAsLinesSync();
    expect(afterManual, hasLength(updatedLines.length + 1));
    expect(jsonDecode(afterManual.last)['action'], 'manual checkpoint');
  }, options: const CaptureOptions(mode: CaptureMode.always));

  capturePatrolWidgetTest(
    'records overridden patrol actions without entered text',
    ($) async {
      var held = false;
      await $.pumpWidgetAndSettle(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => Scaffold(
              body: Column(
                children: [
                  const TextField(key: ValueKey('field')),
                  GestureDetector(
                    key: const ValueKey('hold'),
                    behavior: HitTestBehavior.opaque,
                    onLongPress: () => setState(() => held = true),
                    child: ColoredBox(
                      color: held ? Colors.blue : Colors.red,
                      child: const SizedBox(width: 160, height: 48),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      key: const ValueKey('list'),
                      itemCount: 30,
                      itemBuilder: (context, index) => SizedBox(
                        height: 80,
                        child:
                            Text('item-$index', key: ValueKey('item-$index')),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      const secret = 'secret-input-value';
      await $.enterText(find.byKey(const ValueKey('field')), secret);
      await $.longPress(find.byKey(const ValueKey('hold')));
      expect(held, isTrue);
      await $.dragUntilVisible(
        finder: find.byKey(const ValueKey('item-20')),
        view: find.byKey(const ValueKey('list')),
        moveStep: const Offset(0, -300),
      );
      final manifest =
          File('${$.session.directory.path}/manifest.jsonl').readAsStringSync();
      expect(manifest, isNot(contains(secret)));
      expect(
        [
          for (final line in manifest.split('\n'))
            if (line.trim().isNotEmpty)
              (jsonDecode(line) as Map<String, dynamic>)['action'],
        ],
        ['start', 'enterText', 'longPress', 'scrollTo'],
      );
    },
    options: const CaptureOptions(mode: CaptureMode.always),
  );
}
