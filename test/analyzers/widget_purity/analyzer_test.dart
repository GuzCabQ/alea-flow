// Tests for the widget_purity analyzer.
//
// Rules covered:
//   1. build_heavy_loop — for/while/do-while loop directly inside build().
//   2. sort_in_build   — .sort() with a target (or cascaded) directly inside build().
//
// WP10 FIX NOTE:
//   A bare `sort()` call with no target inside build() IS now flagged.
//   Any sort() directly in build() is suspect, with or without a receiver.

import 'dart:io';

import 'package:alea_flow/alea_flow.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('WidgetPurityAnalyzer', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('alea_purity_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    // ── helpers ──────────────────────────────────────────────────────────────

    Future<AnalysisResult> runOn(String dartSource) async {
      final file = File(p.join(tmp.path, 'fixture.dart'))
        ..writeAsStringSync(dartSource);
      return WidgetPurityAnalyzer().analyze(
        AnalyzerContext(
          filePaths: [file.path],
          projectRoot: tmp.path,
          config: _minimalConfig(),
        ),
      );
    }

    // ── clean: build() with no loops or sorts ────────────────────────────────

    test('emits no issues for a pure build() with no loops or sorts', () async {
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

    test('emits no issues when a for loop is outside build()', () async {
      const src = '''
class MyWidget {
  List<Widget> makeItems(List<String> labels) {
    final out = <Widget>[];
    for (final l in labels) {
      out.add(Text(l));
    }
    return out;
  }
  Widget build(BuildContext context) => Column(children: makeItems(['a', 'b']));
}
''';
      final result = await runOn(src);
      expect(result.issues, isEmpty);
    });

    // ── violation: for loop inside build() ───────────────────────────────────

    test('flags a for loop directly inside build()', () async {
      const src = '''
class MyWidget {
  final List<String> items = [];
  Widget build(BuildContext context) {
    final widgets = <Widget>[];
    for (final item in items) {
      widgets.add(Text(item));
    }
    return Column(children: widgets);
  }
}
''';
      final result = await runOn(src);
      final loopIssues = result.issues
          .where((i) => i.rule == 'build_heavy_loop')
          .toList();
      expect(loopIssues, hasLength(1));
      expect(loopIssues.first.ruleId, 'widget_purity/build_heavy_loop');
      expect(loopIssues.first.severity, Severity.major);
      expect(loopIssues.first.message, contains('for'));
      expect(loopIssues.first.line, 5);
    });

    // ── violation: while loop inside build() ─────────────────────────────────

    test('flags a while loop directly inside build()', () async {
      const src = '''
class MyWidget {
  Widget build(BuildContext context) {
    var i = 0;
    while (i < 10) { i++; }
    return Container();
  }
}
''';
      final result = await runOn(src);
      final loopIssues = result.issues
          .where((i) => i.rule == 'build_heavy_loop')
          .toList();
      expect(loopIssues, hasLength(1));
      expect(loopIssues.first.message, contains('while'));
    });

    // ── violation: do-while loop inside build() ───────────────────────────────

    test('flags a do-while loop directly inside build()', () async {
      const src = '''
class MyWidget {
  Widget build(BuildContext context) {
    var i = 0;
    do { i++; } while (i < 5);
    return Container();
  }
}
''';
      final result = await runOn(src);
      final loopIssues = result.issues
          .where((i) => i.rule == 'build_heavy_loop')
          .toList();
      expect(loopIssues, hasLength(1));
      expect(loopIssues.first.message, contains('do-while'));
    });

    // ── loops inside closures in build() are exempt ───────────────────────────

    test('does NOT flag a for loop inside a closure inside build()', () async {
      // The closure depth guard (_closureDepthInBuild > 0) exempts loops
      // inside builder callbacks, etc.
      const src = '''
class MyWidget {
  final List<String> items = [];
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (ctx, index) {
        final widgets = <Widget>[];
        for (final item in items) {
          widgets.add(Text(item));
        }
        return Column(children: widgets);
      },
    );
  }
}
''';
      final result = await runOn(src);
      final loopIssues = result.issues
          .where((i) => i.rule == 'build_heavy_loop')
          .toList();
      expect(loopIssues, isEmpty);
    });

    // ── violation: .sort() with a target inside build() ──────────────────────

    test('flags list.sort() directly inside build()', () async {
      const src = '''
class MyWidget {
  final List<int> nums = [];
  Widget build(BuildContext context) {
    nums.sort();
    return Container();
  }
}
''';
      final result = await runOn(src);
      final sortIssues = result.issues
          .where((i) => i.rule == 'sort_in_build')
          .toList();
      expect(sortIssues, hasLength(1));
      expect(sortIssues.first.ruleId, 'widget_purity/sort_in_build');
      expect(sortIssues.first.severity, Severity.major);
      expect(sortIssues.first.line, 4);
    });

    test('flags cascaded ..sort() directly inside build()', () async {
      const src = '''
class MyWidget {
  final List<int> nums = [];
  Widget build(BuildContext context) {
    nums..sort();
    return Container();
  }
}
''';
      final result = await runOn(src);
      final sortIssues = result.issues
          .where((i) => i.rule == 'sort_in_build')
          .toList();
      expect(sortIssues, hasLength(1));
    });

    test('does NOT flag list.sort() outside build()', () async {
      const src = '''
class MyWidget {
  final List<int> nums = [];
  List<int> sortedNums() {
    final copy = List.of(nums);
    copy.sort();
    return copy;
  }
  Widget build(BuildContext context) => Text('\${sortedNums()}');
}
''';
      final result = await runOn(src);
      final sortIssues = result.issues
          .where((i) => i.rule == 'sort_in_build')
          .toList();
      expect(sortIssues, isEmpty);
    });

    test('does NOT flag .sort() inside a closure inside build()', () async {
      const src = '''
class MyWidget {
  final List<int> nums = [];
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () { nums.sort(); },
      child: Container(),
    );
  }
}
''';
      final result = await runOn(src);
      final sortIssues = result.issues
          .where((i) => i.rule == 'sort_in_build')
          .toList();
      expect(sortIssues, isEmpty);
    });

    // ── FIX: bare sort() without target IS now flagged ────────────────────────
    //
    // Any sort() directly inside build() is suspect — with or without a receiver.
    // The _directlyInBuild gate ensures sort() outside build() is still clean.
    test(
      'flags a bare sort() call with no target directly inside build()',
      () async {
        const src = '''
class MyWidget {
  Widget build(BuildContext context) {
    sort(); // bare call — no target
    return Container();
  }
}
''';
        final result = await runOn(src);
        final sortIssues = result.issues
            .where((i) => i.rule == 'sort_in_build')
            .toList();
        // Fixed behavior: flagged as a violation.
        expect(sortIssues, hasLength(1));
        expect(sortIssues.first.ruleId, 'widget_purity/sort_in_build');
      },
    );

    // ── multiple issues in one file ──────────────────────────────────────────

    test('reports multiple issues in the same build()', () async {
      const src = '''
class MyWidget {
  final List<int> nums = [];
  Widget build(BuildContext context) {
    nums.sort();
    for (final n in nums) { print(n); }
    while (false) {}
    return Container();
  }
}
''';
      final result = await runOn(src);
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
