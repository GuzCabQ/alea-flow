// Tests for the performance analyzer.
//
// Strategy: write Dart fixture strings to a temp file, run the analyzer over
// them, and assert on the resulting issues. This matches the characterization
// approach: we assert CURRENT behavior; do not change product code.
//
// Rules covered by the analyzer:
//   1. expensive_operation_in_build — .where/.sort/.expand/.fold/.reduce/.toMap
//      called inside build().
//   2. image_network_no_cache — Image.network() without cacheWidth/cacheHeight.

import 'dart:io';

import 'package:alea_flow/alea_flow.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('PerformanceAnalyzer', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('alea_perf_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    // ── helpers ──────────────────────────────────────────────────────────────

    Future<AnalysisResult> runOn(String dartSource) async {
      final file = File(p.join(tmp.path, 'fixture.dart'))
        ..writeAsStringSync(dartSource);
      return PerformanceAnalyzer().analyze(
        AnalyzerContext(
          filePaths: [file.path],
          projectRoot: tmp.path,
          config: _minimalConfig(),
        ),
      );
    }

    // ── clean: cheap work inside build() → no issues ─────────────────────────

    test('emits no issues for a build() doing only cheap work', () async {
      const src = '''
class MyWidget {
  Widget build(BuildContext context) {
    final title = 'hello';
    return Text(title);
  }
}
''';
      final result = await runOn(src);
      expect(result.issues, isEmpty);
    });

    // ── violation: expensive call inside build() ─────────────────────────────

    test(
      'flags .where() inside build() with rule expensive_operation_in_build',
      () async {
        const src = '''
class MyWidget {
  final List<int> items = [];
  Widget build(BuildContext context) {
    final evens = items.where((i) => i.isEven);
    return Container();
  }
}
''';
        final result = await runOn(src);
        expect(result.issues, hasLength(1));
        expect(result.issues.first.rule, 'expensive_operation_in_build');
        expect(result.issues.first.ruleId, 'performance/expensive_in_build');
        expect(result.issues.first.severity, Severity.major);
        expect(result.issues.first.line, 4);
      },
    );

    test('flags .sort() inside build()', () async {
      const src = '''
class MyWidget {
  final List<int> items = [];
  Widget build(BuildContext context) {
    items.sort();
    return Container();
  }
}
''';
      final result = await runOn(src);
      // The performance analyzer uses _expensiveMethods which includes 'sort'.
      expect(result.issues, hasLength(1));
      expect(result.issues.first.rule, 'expensive_operation_in_build');
    });

    test('flags .fold() inside build()', () async {
      const src = '''
class MyWidget {
  final List<int> items = [];
  Widget build(BuildContext context) {
    final sum = items.fold(0, (a, b) => a + b);
    return Text('\$sum');
  }
}
''';
      final result = await runOn(src);
      expect(result.issues, hasLength(1));
      expect(result.issues.first.rule, 'expensive_operation_in_build');
    });

    test('does NOT flag expensive call outside build()', () async {
      const src = '''
class MyWidget {
  final List<int> items = [];

  List<int> computeEvens() {
    return items.where((i) => i.isEven).toList();
  }

  Widget build(BuildContext context) {
    return Text('\${computeEvens().length}');
  }
}
''';
      final result = await runOn(src);
      expect(result.issues, isEmpty);
    });

    // ── Image.network without cache ──────────────────────────────────────────

    test('flags Image.network() without cacheWidth/cacheHeight', () async {
      const src = '''
Widget build(BuildContext ctx) {
  return Image.network('https://example.com/img.png');
}
''';
      final result = await runOn(src);
      // Expect the image_network_no_cache issue.
      final imgIssues = result.issues
          .where((i) => i.rule == 'image_network_no_cache')
          .toList();
      expect(imgIssues, hasLength(1));
      expect(imgIssues.first.ruleId, 'performance/image_no_cache');
      expect(imgIssues.first.severity, Severity.minor);
    });

    test('does NOT flag Image.network() with cacheWidth set', () async {
      const src = '''
Widget build(BuildContext ctx) {
  return Image.network('https://example.com/img.png', cacheWidth: 200);
}
''';
      final result = await runOn(src);
      final imgIssues = result.issues
          .where((i) => i.rule == 'image_network_no_cache')
          .toList();
      expect(imgIssues, isEmpty);
    });

    test('does NOT flag Image.network() with cacheHeight set', () async {
      const src = '''
Widget build(BuildContext ctx) {
  return Image.network('https://example.com/img.png', cacheHeight: 150);
}
''';
      final result = await runOn(src);
      final imgIssues = result.issues
          .where((i) => i.rule == 'image_network_no_cache')
          .toList();
      expect(imgIssues, isEmpty);
    });

    // Note: image_network_no_cache fires even OUTSIDE build() because the
    // analyzer checks it in visitMethodInvocation regardless of _inBuildMethod.
    test(
      'Image.network without cache is flagged even outside build()',
      () async {
        const src = '''
class MyWidget {
  Widget makeImage() {
    return Image.network('https://example.com/img.png');
  }
  Widget build(BuildContext ctx) => makeImage();
}
''';
        final result = await runOn(src);
        final imgIssues = result.issues
            .where((i) => i.rule == 'image_network_no_cache')
            .toList();
        // Characterization: the analyzer flags Image.network unconditionally.
        expect(imgIssues, hasLength(1));
      },
    );

    // ── multiple issues in one file ──────────────────────────────────────────

    test('reports multiple issues in the same file', () async {
      const src = '''
class MyWidget {
  final List<int> nums = [];
  Widget build(BuildContext ctx) {
    final filtered = nums.where((n) => n > 0);
    final summed = nums.fold(0, (a, b) => a + b);
    return Image.network('https://example.com/img.png');
  }
}
''';
      final result = await runOn(src);
      // 2 expensive_in_build + 1 image_no_cache
      expect(result.issues.length, greaterThanOrEqualTo(3));
    });
  });
}

// ── Minimal ProjectConfig ────────────────────────────────────────────────────

ProjectConfig _minimalConfig() => const ProjectConfig(
  configVersion: '1.0.0',
  project: ProjectInfo(packageName: 'test_app', pubspecPath: 'pubspec.yaml'),
  architecture: ArchitectureConfig(layers: {}),
  stateManagement: StateManagementConfig(style: 'none'),
  routing: RoutingConfig(package: 'none', routerPath: ''),
  theme: ThemeConfig(path: ''),
  testing: TestingConfig(framework: 'dart_test', fakesPath: 'test/fakes/'),
  coverage: CoverageConfig(thresholds: {}),
  ticketSource: TicketSourceConfig(adapter: 'file'),
  designSource: DesignSourceConfig(defaultAdapter: 'file'),
  mr: MrConfig(
    policy: 'single-commit-amend',
    branchPattern: 'feature/{ticket_id}-{slug}',
    prePush: [],
  ),
  pipeline: PipelineOpsConfig(
    defaultMode: 'guided',
    modesAvailable: ['guided'],
    costWarnUsd: 0,
    costHardStopUsd: 0,
    unreliableThreshold: UnreliableThresholdConfig(
      runsWindow: 5,
      badRunsRequired: 3,
      manualCorrectionsPerRun: 5,
    ),
  ),
  gates: GatesConfig(perLayer: {}),
  analyzers: AnalyzersConfig(),
);
