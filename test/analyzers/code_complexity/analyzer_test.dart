// Tests for code_complexity, focused on the CC-1 calibration: value-object
// equality surface (`operator ==`, `hashCode`) is exempt from CYCLOMATIC
// complexity. Those methods accrue a high McCabe count purely from the flat
// `&&` chain over fields — a metric artifact, not real branching logic. The
// exemption is cyclomatic-only: a genuinely long `==` still trips length.
//
// parseFile is syntactic, so fixtures need no real imports.

import 'dart:io';

import 'package:alea_flow/alea_flow.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group(
    'CodeComplexityAnalyzer — CC-1 equality/hashCode cyclomatic exemption',
    () {
      late Directory dir;
      setUp(() => dir = Directory.systemTemp.createTempSync('alea_cc_'));
      tearDown(() => dir.deleteSync(recursive: true));

      Future<List<AnalysisIssue>> run(
        String source, {
        required CodeComplexityAnalyzer analyzer,
      }) async {
        final file = File(p.join(dir.path, 's.dart'))
          ..writeAsStringSync(source);
        final result = await analyzer.analyze(
          AnalyzerContext(
            filePaths: [file.path],
            projectRoot: dir.path,
            config: _config(),
          ),
        );
        return result.issues;
      }

      bool hasCyclomatic(List<AnalysisIssue> issues) =>
          issues.any((i) => i.ruleId!.startsWith('code_complexity/cyclomatic'));

      test(
        'does NOT flag a high-cyclomatic operator == on cyclomatic',
        () async {
          const src = '''
class C {
  final int a, b, c, d;
  const C(this.a, this.b, this.c, this.d);
  @override
  bool operator ==(Object o) =>
      o is C && o.a == a && o.b == b && o.c == c && o.d == d;
}
''';
          final issues = await run(
            src,
            analyzer: CodeComplexityAnalyzer(
              complexityThresholdMajor: 2,
              complexityThresholdCritical: 3,
            ),
          );
          expect(hasCyclomatic(issues), isFalse);
        },
      );

      test(
        'does NOT flag a high-cyclomatic hashCode getter on cyclomatic',
        () async {
          const src = '''
class C {
  final bool a, b, c, d;
  const C(this.a, this.b, this.c, this.d);
  @override
  int get hashCode =>
      (a ? 1 : 0) + (b ? 2 : 0) + (c ? 3 : 0) + (d ? 4 : 0);
}
''';
          final issues = await run(
            src,
            analyzer: CodeComplexityAnalyzer(
              complexityThresholdMajor: 2,
              complexityThresholdCritical: 3,
            ),
          );
          expect(hasCyclomatic(issues), isFalse);
        },
      );

      test('STILL flags a regular method with high cyclomatic', () async {
        const src = '''
class C {
  void doStuff(int x) {
    if (x == 1) {}
    if (x == 2) {}
    if (x == 3) {}
    if (x == 4) {}
  }
}
''';
        final issues = await run(
          src,
          analyzer: CodeComplexityAnalyzer(
            complexityThresholdMajor: 2,
            complexityThresholdCritical: 3,
          ),
        );
        final cyc = issues
            .where((i) => i.ruleId == 'code_complexity/cyclomatic_critical')
            .toList();
        expect(cyc, hasLength(1));
      });

      test(
        'STILL flags a long operator == on length (exemption is cyclomatic-only)',
        () async {
          final body = List.generate(
            8,
            (i) => '        o.f$i == f$i',
          ).join(' &&\n');
          final src =
              '''
class C {
  final int f0, f1, f2, f3, f4, f5, f6, f7;
  const C(this.f0, this.f1, this.f2, this.f3, this.f4, this.f5, this.f6, this.f7);
  @override
  bool operator ==(Object o) {
    return o is C &&
$body;
  }
}
''';
          final issues = await run(
            src,
            analyzer: CodeComplexityAnalyzer(
              complexityThresholdCritical: 100, // don't trip cyclomatic
              lengthThresholdMajor: 2,
              lengthThresholdCritical: 4,
            ),
          );
          expect(
            issues.any((i) => i.ruleId!.startsWith('code_complexity/length')),
            isTrue,
            reason: 'length is independent of the cyclomatic exemption',
          );
        },
      );
    },
  );
}

ProjectConfig _config() {
  return ProjectConfig(
    configVersion: '1.0.0',
    project: const ProjectInfo(
      packageName: 'sample_app',
      pubspecPath: 'pubspec.yaml',
    ),
    architecture: const ArchitectureConfig(
      layers: {
        'domain': LayerConfig(paths: ['lib/src/domain/']),
      },
    ),
    stateManagement: const StateManagementConfig(style: 'riverpod_manual'),
    routing: const RoutingConfig(
      package: 'go_router',
      routerPath: 'lib/app/router/app_router.dart',
    ),
    theme: const ThemeConfig(path: 'lib/app/theme/app_theme.dart'),
    testing: const TestingConfig(
      framework: 'flutter_test',
      fakesPath: 'test/fakes/',
    ),
    coverage: const CoverageConfig(thresholds: {'domain': 95}),
    ticketSource: const TicketSourceConfig(adapter: 'asana'),
    designSource: const DesignSourceConfig(defaultAdapter: 'figma'),
    mr: const MrConfig(
      policy: 'single-commit-amend',
      branchPattern: 'feature/{ticket_id}-{slug}',
      prePush: ['dart format .', 'dart analyze', 'flutter test'],
    ),
    pipeline: const PipelineOpsConfig(
      defaultMode: 'guided',
      modesAvailable: ['guided', 'semi', 'auto'],
      costWarnUsd: 3.0,
      costHardStopUsd: 5.0,
      unreliableThreshold: UnreliableThresholdConfig(
        runsWindow: 5,
        badRunsRequired: 3,
        manualCorrectionsPerRun: 5,
      ),
    ),
    gates: const GatesConfig(
      perLayer: {
        'domain': ['domain'],
      },
    ),
    analyzers: const AnalyzersConfig(),
  );
}
