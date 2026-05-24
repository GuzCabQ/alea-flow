// Tests for the meaningful_test analyzer (ADVISORY — severity minor, never
// blocks). Fixtures are written to a temp dir at runtime because they must end
// in `_test.dart` (the analyzer's filter) and would otherwise be collected and
// run by the test runner itself.

import 'dart:io';

import 'package:alea_flow/alea_flow.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('MeaningfulTestAnalyzer', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('alea_mt_'));
    tearDown(() => dir.deleteSync(recursive: true));

    Future<AnalysisResult> analyzeSource(String fileName, String source) {
      final file = File(p.join(dir.path, fileName))..writeAsStringSync(source);
      return MeaningfulTestAnalyzer().analyze(
        AnalyzerContext(
          filePaths: [file.path],
          projectRoot: dir.path,
          config: _config(),
        ),
      );
    }

    test('flags tautological expects', () async {
      final result = await analyzeSource('taut_test.dart', '''
import 'package:test/test.dart';
void main() {
  test('taut', () {
    expect(true, true);
    expect(x, x);
  });
}
''');
      final taut = result.issues
          .where((i) => i.ruleId == 'meaningful_test/tautological_expect')
          .toList();
      expect(taut, hasLength(2));
      expect(taut.every((i) => i.severity == Severity.minor), isTrue);
    });

    test('flags a test with no assertion', () async {
      final result = await analyzeSource('empty_test.dart', '''
import 'package:test/test.dart';
void main() {
  test('does nothing', () {
    final x = 1 + 1;
  });
}
''');
      expect(result.issues, hasLength(1));
      expect(result.issues.single.ruleId, 'meaningful_test/no_assertion');
      expect(result.issues.single.severity, Severity.minor);
    });

    test('a real assertion produces no issues', () async {
      final result = await analyzeSource('good_test.dart', '''
import 'package:test/test.dart';
void main() {
  test('real', () {
    expect(2 + 2, equals(4));
  });
}
''');
      expect(result.issues, isEmpty);
    });

    test('verify() counts as an assertion (no no_assertion)', () async {
      final result = await analyzeSource('verify_test.dart', '''
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
void main() {
  test('with verify', () {
    verify(() => mock.foo()).called(1);
  });
}
''');
      expect(result.issues, isEmpty);
    });

    test('is advisory: minor issues never reprueban el gate', () async {
      final result = await analyzeSource('taut2_test.dart', '''
import 'package:test/test.dart';
void main() {
  test('taut', () { expect(true, true); });
}
''');
      expect(result.issues, isNotEmpty);
      expect(result.passed, isTrue); // minor → gate still passes
    });

    test('ignores non-_test.dart files', () async {
      final result = await analyzeSource('helper.dart', '''
void main() {
  expect(true, true);
}
''');
      expect(result.issues, isEmpty);
    });
  });
}

// Minimal ProjectConfig — meaningful_test ignores config; this just satisfies
// the required AnalyzerContext field.
ProjectConfig _config() => ProjectConfig(
  configVersion: '1.0.0',
  project: const ProjectInfo(packageName: 'demo', pubspecPath: 'pubspec.yaml'),
  architecture: const ArchitectureConfig(
    layers: {
      'domain': LayerConfig(paths: ['lib/src/domain/']),
    },
  ),
  stateManagement: const StateManagementConfig(style: 'riverpod_manual'),
  routing: const RoutingConfig(
    package: 'go_router',
    routerPath: 'lib/src/app/router.dart',
  ),
  theme: const ThemeConfig(path: 'lib/src/theme/'),
  testing: const TestingConfig(
    framework: 'flutter_test',
    fakesPath: 'test/fakes/',
  ),
  coverage: const CoverageConfig(thresholds: {'domain': 80}),
  ticketSource: const TicketSourceConfig(adapter: 'file'),
  designSource: const DesignSourceConfig(defaultAdapter: 'figma'),
  mr: const MrConfig(
    policy: 'single-commit-amend',
    branchPattern: 'feature/{ticket_id}-{slug}',
    prePush: [],
  ),
  pipeline: const PipelineOpsConfig(
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
  gates: const GatesConfig(perLayer: {}),
  analyzers: const AnalyzersConfig(),
);
