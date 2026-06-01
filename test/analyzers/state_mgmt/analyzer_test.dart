// Tests for the state_mgmt analyzer.
//
// Rules covered (riverpod_manual preset only):
//   1. ref_watch_in_notifier  — ref.watch() inside a Notifier method (not build()).
//   2. provider_in_build      — a call ending in "Provider" directly inside build().
//
// The analyzer is a no-op unless config.state_management.style == 'riverpod_manual'.
//
// WP10 FIX NOTE:
//   The provider_in_build check now restricts to PascalCase names only.
//   Local helpers like buildLoginProvider() (lowercase-initial) are NOT flagged.
//   Real provider constructors like StateProvider(...) are still flagged.

import 'dart:io';

import 'package:alea_flow/alea_flow.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('StateMgmtAnalyzer', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('alea_stmgmt_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    // ── helpers ──────────────────────────────────────────────────────────────

    Future<AnalysisResult> runOn(
      String dartSource, {
      String style = 'riverpod_manual',
    }) async {
      final file = File(p.join(tmp.path, 'fixture.dart'))
        ..writeAsStringSync(dartSource);
      return StateMgmtAnalyzer().analyze(
        AnalyzerContext(
          filePaths: [file.path],
          projectRoot: tmp.path,
          config: _configWithStyle(style),
        ),
      );
    }

    // ── config guard: non-riverpod style emits nothing ────────────────────────

    test('emits no issues when style is not riverpod_manual', () async {
      const src = '''
class AuthNotifier {
  void doSomething() {
    ref.watch(someProvider);
  }
}
''';
      final result = await runOn(src, style: 'bloc');
      expect(result.issues, isEmpty);
    });

    test('emits no issues when style is none', () async {
      const src = '''
class AuthNotifier {
  void doSomething() {
    ref.watch(someProvider);
  }
}
''';
      final result = await runOn(src, style: 'none');
      expect(result.issues, isEmpty);
    });

    // ── clean: correct Riverpod usage ─────────────────────────────────────────

    test('emits no issues for a notifier that only calls ref.read()', () async {
      const src = '''
class AuthNotifier {
  void login(String email) {
    final service = ref.read(authServiceProvider);
    service.login(email);
  }
  Object build() => const Object();
}
''';
      final result = await runOn(src);
      expect(result.issues, isEmpty);
    });

    test('emits no issues when ref.watch() is used inside build()', () async {
      // ref.watch() in build() is correct Riverpod usage.
      const src = '''
class CounterNotifier {
  int build() {
    ref.watch(otherProvider);
    return 0;
  }
}
''';
      final result = await runOn(src);
      expect(result.issues, isEmpty);
    });

    test(
      'emits no issues for a plain widget class without Notifier suffix',
      () async {
        const src = '''
class MyWidget {
  void configure() {
    ref.watch(someProvider);
  }
}
''';
        final result = await runOn(src);
        // Not a *Notifier class → rule does not apply.
        expect(result.issues, isEmpty);
      },
    );

    // ── violation: ref.watch() inside Notifier method ────────────────────────

    test('flags ref.watch() inside a Notifier method (non-build)', () async {
      const src = '''
class AuthNotifier {
  void fetchUser() {
    final user = ref.watch(userProvider);
  }
}
''';
      final result = await runOn(src);
      final watchIssues = result.issues
          .where((i) => i.rule == 'ref_watch_in_notifier')
          .toList();
      expect(watchIssues, hasLength(1));
      expect(
        watchIssues.first.ruleId,
        'state_mgmt/ref_watch_in_notifier_method',
      );
      expect(watchIssues.first.severity, Severity.major);
      expect(watchIssues.first.line, 3);
    });

    test('flags ref.watch() in multiple Notifier methods', () async {
      const src = '''
class UserNotifier {
  void methodA() {
    ref.watch(aProvider);
  }
  void methodB() {
    ref.watch(bProvider);
  }
}
''';
      final result = await runOn(src);
      final watchIssues = result.issues
          .where((i) => i.rule == 'ref_watch_in_notifier')
          .toList();
      expect(watchIssues, hasLength(2));
    });

    // ── violation: provider call inside build() ───────────────────────────────

    test(
      'flags a PascalCase Provider() constructor call directly inside build()',
      () async {
        // PascalCase names (e.g. SomeNotifierProvider) are provider constructors.
        const src = '''
class MyWidget {
  Widget build(BuildContext context) {
    final p = SomeNotifierProvider();
    return Container();
  }
}
''';
        final result = await runOn(src);
        final provIssues = result.issues
            .where((i) => i.rule == 'provider_in_build')
            .toList();
        expect(provIssues, hasLength(1));
        expect(provIssues.first.ruleId, 'state_mgmt/provider_in_build');
        expect(provIssues.first.severity, Severity.major);
        expect(provIssues.first.line, 3);
      },
    );

    test(
      'does NOT flag a provider() call inside a closure inside build()',
      () async {
        // The rule guards _closureDepthInBuild > 0 → skipped inside closures.
        const src = '''
class MyWidget {
  Widget build(BuildContext context) {
    final fn = () {
      final p = someNotifierProvider();
      return p;
    };
    return Container();
  }
}
''';
        final result = await runOn(src);
        final provIssues = result.issues
            .where((i) => i.rule == 'provider_in_build')
            .toList();
        expect(provIssues, isEmpty);
      },
    );

    test(
      'does NOT flag a method whose name ends with Provider but has a target',
      () async {
        // node.target != null → rule skips it.
        const src = '''
class MyWidget {
  Widget build(BuildContext context) {
    final p = factory.buildNotifierProvider();
    return Container();
  }
}
''';
        final result = await runOn(src);
        final provIssues = result.issues
            .where((i) => i.rule == 'provider_in_build')
            .toList();
        expect(provIssues, isEmpty);
      },
    );

    // ── FIX: lowercase-initial helper methods ending in Provider are NOT flagged ─
    //
    // Provider CONSTRUCTORS are PascalCase (e.g. StateProvider, LoginProvider).
    // Local helper methods are lowercase-initial (e.g. buildLoginProvider).
    // The rule now restricts to PascalCase names only — no false positives.
    test(
      'does NOT flag a lowercase-initial helper method ending in Provider called from build()',
      () async {
        const src = '''
class MyWidget {
  dynamic buildLoginProvider() => null;
  Widget build(BuildContext context) {
    final p = buildLoginProvider();
    return Container();
  }
}
''';
        final result = await runOn(src);
        final provIssues = result.issues
            .where((i) => i.rule == 'provider_in_build')
            .toList();
        // Fixed behavior: NOT flagged — it is a helper method, not a provider constructor.
        expect(provIssues, isEmpty);
      },
    );

    test(
      'flags a PascalCase provider constructor call directly inside build()',
      () async {
        const src = '''
class MyWidget {
  Widget build(BuildContext context) {
    final p = StateProvider((ref) => 0);
    return Container();
  }
}
''';
        final result = await runOn(src);
        final provIssues = result.issues
            .where((i) => i.rule == 'provider_in_build')
            .toList();
        // PascalCase constructor → still flagged.
        expect(provIssues, hasLength(1));
      },
    );
  });
}

// ── Config factory ────────────────────────────────────────────────────────────

ProjectConfig _configWithStyle(String style) => ProjectConfig(
  configVersion: '1.0.0',
  project: const ProjectInfo(
    packageName: 'test_app',
    pubspecPath: 'pubspec.yaml',
  ),
  architecture: const ArchitectureConfig(layers: {}),
  stateManagement: StateManagementConfig(style: style),
  routing: const RoutingConfig(package: 'none', routerPath: ''),
  theme: const ThemeConfig(path: ''),
  testing: const TestingConfig(
    framework: 'dart_test',
    fakesPath: 'test/fakes/',
  ),
  coverage: const CoverageConfig(thresholds: {}),
  ticketSource: const TicketSourceConfig(adapter: 'file'),
  designSource: const DesignSourceConfig(defaultAdapter: 'file'),
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
