enum CaptureMode {
  off,
  always,
  reportOnError;

  static CaptureMode parse(String value) => switch (value) {
        'off' => off,
        'always' => always,
        'reportOnError' => reportOnError,
        _ => throw FormatException('Unknown capture mode: $value'),
      };
}

const configuredCaptureMode = String.fromEnvironment(
  'CAPTURE_TEST_MODE',
  defaultValue: 'off',
);

const configuredCaptureOnly = String.fromEnvironment('CAPTURE_TEST_ONLY');

CaptureMode globalCaptureMode = CaptureMode.parse(configuredCaptureMode);

CaptureMode modeForTest(String name, CaptureMode? override) {
  if (configuredCaptureOnly.isNotEmpty &&
      !name.toLowerCase().contains(configuredCaptureOnly.toLowerCase())) {
    return CaptureMode.off;
  }
  return override ?? globalCaptureMode;
}
