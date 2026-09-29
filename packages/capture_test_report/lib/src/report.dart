import 'dart:convert';
import 'dart:io';

enum CaptureStatus {
  passed,
  failed,
  unknown;

  static CaptureStatus parse(Object? value) => switch (value) {
        'passed' => passed,
        'failed' => failed,
        _ => unknown,
      };

  String get label => switch (this) {
        passed => 'Passed',
        failed => 'Failed',
        unknown => 'Unknown',
      };
}

class CaptureFrame {
  const CaptureFrame({
    required this.test,
    required this.testGroup,
    required this.layout,
    required this.index,
    required this.action,
    required this.file,
    required this.width,
    required this.height,
    this.status = CaptureStatus.unknown,
    this.target,
    this.screen,
    this.description,
    this.errorType,
    this.errorLocation,
  });

  factory CaptureFrame.fromJson(
    Map<String, dynamic> json, {
    CaptureStatus status = CaptureStatus.unknown,
    String? errorType,
    String? errorLocation,
  }) {
    if (json['schemaVersion'] != 1) {
      throw FormatException(
        'Unsupported capture schema: ${json['schemaVersion']}',
      );
    }
    final test = json['test'] as String;
    final layout = json['layout'] as String;
    final explicitGroup = json['testGroup'] as String?;
    final suffix = ' [$layout]';
    final testGroup = explicitGroup != null && explicitGroup.isNotEmpty
        ? explicitGroup
        : test.endsWith(suffix)
            ? test.substring(0, test.length - suffix.length)
            : test;
    return CaptureFrame(
      test: test,
      testGroup: testGroup,
      layout: layout,
      index: json['index'] as int,
      action: json['action'] as String,
      target: json['target'] as String?,
      screen: json['screen'] as String?,
      description: json['description'] as String?,
      file: json['file'] as String,
      width: json['width'] as int,
      height: json['height'] as int,
      status: status,
      errorType: errorType,
      errorLocation: errorLocation,
    );
  }

  final String test;
  final String testGroup;
  final String layout;
  final int index;
  final String action;
  final String? target;
  final String? screen;
  final String? description;
  final String? errorType;
  final String? errorLocation;
  final String file;
  final int width;
  final int height;
  final CaptureStatus status;
}

List<CaptureFrame> loadFrames(Directory root) {
  if (!root.existsSync()) {
    throw FileSystemException('Capture directory does not exist', root.path);
  }
  final files = root
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('manifest.jsonl'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  final frames = <CaptureFrame>[];
  for (final file in files) {
    final result = File('${file.parent.path}/result.json');
    final outcome = result.existsSync()
        ? jsonDecode(result.readAsStringSync()) as Map<String, dynamic>
        : <String, dynamic>{};
    final status = CaptureStatus.parse(outcome['status']);
    for (final line in file.readAsLinesSync()) {
      if (line.trim().isEmpty) continue;
      frames.add(
        CaptureFrame.fromJson(
          jsonDecode(line) as Map<String, dynamic>,
          status: status,
          errorType: outcome['errorType'] as String?,
          errorLocation: outcome['location'] as String?,
        ),
      );
    }
  }
  frames.sort((a, b) {
    final group = a.testGroup.compareTo(b.testGroup);
    if (group != 0) return group;
    final layout = a.layout.compareTo(b.layout);
    if (layout != 0) return layout;
    return a.index.compareTo(b.index);
  });
  return frames;
}

String renderReport(List<CaptureFrame> frames) {
  final flows = <String, Map<String, List<CaptureFrame>>>{};
  for (final frame in frames) {
    flows
        .putIfAbsent(frame.testGroup, () => {})
        .putIfAbsent(frame.layout, () => [])
        .add(frame);
  }
  final nav = flows.entries.map((flow) {
    final status = _statusFor(flow.value.values.expand((frames) => frames));
    return '<button type="button" class="flow-button" data-flow="${_escape(flow.key)}">'
        '<span class="flow-name">${_escape(flow.key)}</span>'
        '${_badge(status)}</button>';
  }).join();
  final sections = <String>[];
  for (final flow in flows.entries) {
    for (final layout in flow.value.entries) {
      final status = _statusFor(layout.value);
      final failure = layout.value.first;
      final failureDetails = [
        if (failure.errorType != null) failure.errorType!,
        if (failure.errorLocation != null) failure.errorLocation!,
      ];
      final failurePanel = status == CaptureStatus.failed
          ? '<div class="failure"><strong>Test failed</strong>'
              '${failureDetails.isEmpty ? '<p>No failure details recorded.</p>' : '<p>${failureDetails.map(_escape).join(' · ')}</p>'}'
              '</div>'
          : '';
      final cards = layout.value.map((frame) {
        final caption =
            '${frame.index.toString().padLeft(3, '0')} · ${frame.action}'
            '${frame.target == null ? '' : ' · ${frame.target}'}';
        final title = frame.description ?? caption;
        return '<li><a href="${_escape(frame.file)}" target="_blank" rel="noopener">'
            '<img src="${_escape(frame.file)}" loading="lazy" alt="${_escape(caption)}">'
            '</a><p>${_escape(title)}</p>'
            '${frame.description == null ? '' : '<small>${_escape(caption)}</small><br>'}'
            '<small>${_escape(frame.screen ?? '')} · ${frame.width}×${frame.height}</small></li>';
      }).join();
      sections.add(
        '<section data-flow="${_escape(flow.key)}" '
        'data-layout="${_escape(layout.key)}" data-status="${status.name}" hidden>'
        '$failurePanel<ol>$cards</ol></section>',
      );
    }
  }
  return '''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Capture test report</title><style>
:root{color-scheme:light;font-family:system-ui,sans-serif;font-size:15px}
*{box-sizing:border-box}
body{margin:0;background:#f5f5fa;color:#202033;overflow:hidden}
.app{display:grid;grid-template-columns:290px minmax(0,1fr);height:100vh;height:100dvh}
.sidebar{display:flex;flex-direction:column;min-height:0;background:white;border-right:1px solid #dedee7}
.sidebar-head{padding:20px 16px 12px;flex:none}
h1{font-size:19px;margin:0 0 16px}
label{display:block;font-size:13px;font-weight:600;margin-bottom:6px}
input[type=search]{font:inherit;width:100%;border:1px solid #bfc0cc;border-radius:8px;padding:9px 10px}
input[type=search]:focus-visible,button:focus-visible{outline:2px solid #5145c5;outline-offset:2px}
.flow-list{overflow-y:auto;min-height:0;padding:4px 8px 16px;display:flex;flex-direction:column;gap:3px}
button{font:inherit;cursor:pointer;color:inherit}
.flow-button{display:flex;align-items:flex-start;justify-content:space-between;gap:8px;width:100%;border:0;border-radius:8px;background:transparent;padding:10px 8px;text-align:left}
.flow-button[hidden]{display:none}
.flow-button:hover,.flow-button[aria-current=true]{background:#e9e8f8}
.flow-name{min-width:0;overflow-wrap:anywhere}
.badge{display:inline-flex;align-items:center;flex:none;border-radius:999px;font-size:11px;font-weight:700;padding:3px 7px}
.badge.passed{background:#d9f4e3;color:#17663a}.badge.failed{background:#ffe0df;color:#a32520}.badge.unknown{background:#e8e8ee;color:#57576b}
#search-empty{padding:10px 8px;color:#666}
.content{min-width:0;min-height:0;overflow-y:auto}
.toolbar{position:sticky;top:0;z-index:1;background:#f5f5fa;border-bottom:1px solid #dedee7;padding:18px 24px 14px}
.title-row{display:flex;align-items:center;gap:10px;margin-bottom:12px}
h2{font-size:20px;margin:0;overflow-wrap:anywhere}
.variants{display:flex;gap:8px;flex-wrap:wrap}
.variants button{display:flex;align-items:center;gap:7px;background:white;border:1px solid #c8c8d3;border-radius:8px;padding:7px 10px}
.variants button[aria-pressed=true]{background:#e3e1ff;border-color:#7165d6}
.frames{padding:24px}
.failure{border:1px solid #e7a8a5;background:#fff0ef;color:#74221f;border-radius:9px;padding:14px 16px;margin-bottom:20px;overflow-wrap:anywhere}
.failure p{margin:7px 0 0}
section[hidden]{display:none}
ol{list-style:none;padding:0;margin:0;display:grid;grid-template-columns:repeat(auto-fill,minmax(280px,1fr));gap:18px}
li{padding:12px;border:1px solid #ddd;border-radius:9px;background:white;min-width:0}
img{display:block;width:100%;height:auto}li p{font-weight:600;margin:10px 0 2px;overflow-wrap:anywhere}small{color:#666}
@media(max-width:700px){.app{grid-template-columns:1fr;grid-template-rows:minmax(170px,34vh) minmax(0,1fr)}.sidebar{border-right:0;border-bottom:1px solid #dedee7}.toolbar{padding:14px}.frames{padding:14px}}
</style></head><body><div class="app">
<nav class="sidebar" aria-label="Tests"><div class="sidebar-head"><h1>Capture test report</h1>
<label for="test-search">Search tests</label><input id="test-search" type="search" placeholder="Test name" autocomplete="off"></div>
<div class="flow-list" id="flow-list">$nav<p id="search-empty" hidden>No matching tests</p></div></nav>
<main class="content"><div class="toolbar"><div class="title-row"><h2 id="test-title"></h2><span id="test-status"></span></div>
<div class="variants" id="variants" role="group" aria-label="Variants"></div></div>
<div class="frames">${sections.join()}</div></main></div>
<script>
const sections=[...document.querySelectorAll('section')];
const buttons=[...document.querySelectorAll('.flow-button')];
const search=document.getElementById('test-search');
const variants=document.getElementById('variants');
const title=document.getElementById('test-title');
const status=document.getElementById('test-status');
let flow=buttons[0]?.dataset.flow;
let layout;
function badge(value){const span=document.createElement('span');span.className='badge '+value;span.textContent=value[0].toUpperCase()+value.slice(1);return span}
function show(){
  const available=sections.filter(s=>s.dataset.flow===flow);
  if(!available.some(s=>s.dataset.layout===layout))layout=available[0]?.dataset.layout;
  variants.replaceChildren(...available.map(s=>{
    const button=document.createElement('button');button.type='button';button.append(document.createTextNode(s.dataset.layout),badge(s.dataset.status));
    button.setAttribute('aria-pressed',String(s.dataset.layout===layout));
    button.onclick=()=>{layout=s.dataset.layout;show()};return button;
  }));
  title.textContent=flow??'';
  const active=buttons.find(b=>b.dataset.flow===flow);
  status.replaceChildren(...(active?[badge(active.querySelector('.badge').classList[1])]:[]));
  sections.forEach(s=>s.hidden=s.dataset.flow!==flow||s.dataset.layout!==layout);
  buttons.forEach(b=>b.setAttribute('aria-current',String(b===active)));
}
buttons.forEach(b=>b.onclick=()=>{flow=b.dataset.flow;layout=undefined;show()});
search.oninput=()=>{
  const query=search.value.trim().toLocaleLowerCase();
  const visible=buttons.filter(b=>{const match=b.dataset.flow.toLocaleLowerCase().includes(query);b.hidden=!match;return match});
  document.getElementById('search-empty').hidden=visible.length!==0;
  if(!visible.some(b=>b.dataset.flow===flow)){flow=visible[0]?.dataset.flow;layout=undefined}
  show();
};
show();
</script></body></html>''';
}

CaptureStatus _statusFor(Iterable<CaptureFrame> frames) {
  final statuses = frames.map((frame) => frame.status).toSet();
  if (statuses.contains(CaptureStatus.failed)) return CaptureStatus.failed;
  if (statuses.length == 1 && statuses.contains(CaptureStatus.passed)) {
    return CaptureStatus.passed;
  }
  return CaptureStatus.unknown;
}

String _badge(CaptureStatus status) =>
    '<span class="badge ${status.name}">${status.label}</span>';

String _escape(String value) =>
    const HtmlEscape(HtmlEscapeMode.attribute).convert(value);
