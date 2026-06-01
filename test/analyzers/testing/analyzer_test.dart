// Tests for the testing analyzer's expected-test-path resolution.
//
// Regression for the freya parity finding: real Flutter projects mirror `lib/`
// under `test/` (the standard Dart convention) — e.g.
//   lib/src/domain/repositories/x.dart -> test/src/domain/repositories/x_test.dart
// The analyzer previously stripped the layer prefix and looked only at
//   test/repositories/x_test.dart
// which exists in almost no real project, producing a flood of false
// `missing_test` criticals. The analyzer must credit the standard mirror
// layout (and the legacy layer-relative one) and only report missing when no
// test exists under any known convention.
//
// Filesystem-coupled (the analyzer probes the disk for the test file), so
// fixtures are written to a temp dir at runtime.

import 'dart:io';

import 'package:alea_flow/alea_flow.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('TestingAnalyzer expected-test-path', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('alea_testing_'));
    tearDown(() => dir.deleteSync(recursive: true));

    void write(String rel, [String content = '// stub\n']) {
      final f = File(p.join(dir.path, rel));
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(content);
    }

    Future<List<AnalysisIssue>> missingFor(String sourceRel) async {
      final result = await TestingAnalyzer().analyze(
        AnalyzerContext(
          filePaths: [p.join(dir.path, sourceRel)],
          projectRoot: dir.path,
          config: _config(),
        ),
      );
      return result.issues
          .where((i) => i.ruleId == 'testing/missing_test')
          .toList();
    }

    const src = 'lib/src/domain/repositories/profile_repo.dart';

    test(
      'credits lib->test mirror layout (standard Dart convention)',
      () async {
        write(src, 'class ProfileRepo {\n  Future<void> fetch() async {}\n}\n');
        write(
          'test/src/domain/repositories/profile_repo_test.dart',
          'void main() {}\n',
        );
        expect(
          await missingFor(src),
          isEmpty,
          reason: 'a test at the standard lib-mirror path must be credited',
        );
      },
    );

    test('still credits legacy layer-relative layout', () async {
      write(src, 'class ProfileRepo {\n  Future<void> fetch() async {}\n}\n');
      write('test/repositories/profile_repo_test.dart', 'void main() {}\n');
      expect(await missingFor(src), isEmpty);
    });

    test('reports missing when no test exists under any convention', () async {
      write(src, 'class ProfileRepo {\n  Future<void> fetch() async {}\n}\n');
      final missing = await missingFor(src);
      expect(missing, hasLength(1));
      expect(
        missing.single.message,
        contains('test/src/domain/repositories/profile_repo_test.dart'),
        reason: 'the expected path should reflect the standard lib mirror',
      );
      expect(
        missing.single.severity,
        Severity.major,
        reason:
            'missing-test defaults to advisory (non-blocking), not critical',
      );
    });

    test('respects a configured missing_test_severity', () async {
      write(src, 'class ProfileRepo {\n  Future<void> fetch() async {}\n}\n');
      final result = await TestingAnalyzer().analyze(
        AnalyzerContext(
          filePaths: [p.join(dir.path, src)],
          projectRoot: dir.path,
          config: _config(missingTestSeverity: 'critical'),
        ),
      );
      final missing = result.issues
          .where((i) => i.ruleId == 'testing/missing_test')
          .toList();
      expect(missing, hasLength(1));
      expect(
        missing.single.severity,
        Severity.critical,
        reason: 'a strict team can raise missing-test back to blocking',
      );
    });

    // ── Scope exemptions (P3): files with nothing to test ──────────────────

    test('exempts generated files (.g.dart) even with code', () async {
      const gen = 'lib/src/domain/user.g.dart';
      write(gen, 'Map<String, Object?> toJson() => {};\n');
      expect(await missingFor(gen), isEmpty);
    });

    test('exempts plain enum-only files', () async {
      const e = 'lib/src/domain/enums/status.dart';
      write(e, 'enum Status { active, inactive }\n');
      expect(await missingFor(e), isEmpty);
    });

    test('exempts constants-only files', () async {
      const c = 'lib/src/domain/constants/keys.dart';
      write(c, "const storageKey = 'k';\nconst timeoutSeconds = 30;\n");
      expect(await missingFor(c), isEmpty);
    });

    test('exempts barrel files (directives only)', () async {
      const b = 'lib/src/domain/domain.dart';
      write(b, "export 'enums/status.dart';\n");
      expect(await missingFor(b), isEmpty);
    });

    test(
      'exempts pure data classes (fields + constructor, no methods)',
      () async {
        const m = 'lib/src/domain/models/point.dart';
        write(m, 'class Point {\n  final int x;\n  const Point(this.x);\n}\n');
        expect(await missingFor(m), isEmpty);
      },
    );

    test('still flags a class that declares methods', () async {
      const s = 'lib/src/domain/user_service.dart';
      write(s, 'class UserService {\n  void doWork() {}\n}\n');
      expect(await missingFor(s), hasLength(1));
    });

    test('still flags an enhanced enum that declares methods', () async {
      const e = 'lib/src/domain/enums/role.dart';
      write(
        e,
        'enum Role {\n  admin, user;\n  bool get isAdmin => this == Role.admin;\n}\n',
      );
      expect(await missingFor(e), hasLength(1));
    });
  });
}

ProjectConfig _config({String missingTestSeverity = 'major'}) {
  return ProjectConfig(
    configVersion: '1.0.0',
    project: const ProjectInfo(
      packageName: 'sample_app',
      pubspecPath: 'pubspec.yaml',
    ),
    architecture: const ArchitectureConfig(
      layers: {
        'domain': LayerConfig(paths: ['lib/src/domain/']),
        'infrastructure': LayerConfig(paths: ['lib/src/infrastructure/']),
        'presentation': LayerConfig(paths: ['lib/src/presentation/']),
      },
    ),
    stateManagement: const StateManagementConfig(style: 'riverpod_manual'),
    routing: const RoutingConfig(
      package: 'go_router',
      routerPath: 'lib/app/router/app_router.dart',
    ),
    theme: const ThemeConfig(path: 'lib/app/theme/app_theme.dart'),
    testing: TestingConfig(
      framework: 'flutter_test',
      fakesPath: 'test/fakes/',
      preferFakesOverMocks: false,
      missingTestSeverity: missingTestSeverity,
    ),
    coverage: const CoverageConfig(
      thresholds: {'domain': 95, 'infrastructure': 80, 'presentation': 70},
    ),
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
        'infrastructure': ['infra'],
        'presentation': ['presentation'],
        'bugfix': ['bugfix'],
      },
    ),
    analyzers: const AnalyzersConfig(),
  );
}
