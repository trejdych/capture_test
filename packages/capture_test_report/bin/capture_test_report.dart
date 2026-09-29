import 'dart:io';

import 'package:capture_test_report/capture_test_report.dart';

void main(List<String> arguments) {
  if (arguments.contains('--help') || arguments.contains('-h')) {
    stdout.writeln('Usage: dart run capture_test_report [capture-directory]');
    stdout.writeln('Default directory: build/captures');
    return;
  }
  if (arguments.length > 1) {
    stderr.writeln('Expected one capture directory. Use --help for usage.');
    exitCode = 64;
    return;
  }
  final root =
      Directory(arguments.isEmpty ? 'build/captures' : arguments.single);
  try {
    final frames = loadFrames(root);
    if (frames.isEmpty) {
      stderr.writeln('No capture manifests found in ${root.path}.');
      exitCode = 1;
      return;
    }
    final output = File('${root.path}/report.html');
    output.writeAsStringSync(renderReport(frames));
    stdout.writeln('${output.path} · ${frames.length} frames');
  } on Object catch (error) {
    stderr.writeln('Could not generate capture report: $error');
    exitCode = 1;
  }
}
