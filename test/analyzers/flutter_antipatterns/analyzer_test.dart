// Tests for the flutter_antipatterns analyzer, focused on context_after_async.
//
// Regression for the freya parity finding: the rule flagged `context` passed
// as an ARGUMENT to the awaited call itself (`await showDialog(context: ...)`),
// which is evaluated BEFORE the await suspends and is therefore safe. The fix
// compares context offsets against the END of the await expression, not its
// start. Genuine post-await context usage must still be flagged.
//
// parseFile is purely syntactic, so fixtures need no real Flutter imports.

import 'dart:io';

import 'package:alea_flow/alea_flow.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('FlutterAntipatternsAnalyzer — context_after_async', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('alea_fap_'));
    tearDown(() => dir.deleteSync(recursive: true));

    Future<List<AnalysisIssue>> run(String source) async {
      final file = File(p.join(dir.path, 'w.dart'))..writeAsStringSync(source);
      final result = await FlutterAntipatternsAnalyzer().analyze(
        AnalyzerContext(
          filePaths: [file.path],
          projectRoot: dir.path,
          config: _config(),
        ),
      );
      return result.issues
          .where((i) => i.ruleId == 'flutter_antipatterns/context_after_async')
          .toList();
    }

    test(
      'does NOT flag context passed as an argument to the awaited call',
      () async {
        const src = '''
class W {
  Future<void> open(BuildContext context) async {
    await showDialog(context: context, builder: (c) => c);
  }
}
''';
        expect(
          await run(src),
          isEmpty,
          reason: 'context in the awaited call args is read before suspension',
        );
      },
    );

    test('still flags context used after the await completes', () async {
      const src = '''
class W {
  Future<void> close(BuildContext context) async {
    await doWork();
    Navigator.of(context).pop();
  }
}
''';
      expect(await run(src), hasLength(1));
    });

    test(
      'does not flag when a mounted check guards the post-await usage',
      () async {
        const src = '''
class W {
  Future<void> guarded(BuildContext context) async {
    await doWork();
    if (!context.mounted) return;
    Navigator.of(context).pop();
  }
}
''';
        expect(await run(src), isEmpty);
      },
    );

    test(
      'flags post-await context use when mounted check comes AFTER it',
      () async {
        const src = '''
class W {
  Future<void> f(BuildContext context) async {
    await Future<void>.delayed(Duration.zero);
    Navigator.of(context).pop();
    if (mounted) setState(() {});
  }
}
''';
        expect(
          await run(src),
          isNotEmpty,
          reason:
              'mounted guard appears after the unguarded context use — '
              'still a violation',
        );
      },
    );

    test(
      'does not flag when mounted guard precedes the post-await context use',
      () async {
        const src = '''
class W {
  Future<void> f(BuildContext context) async {
    await doWork();
    if (!mounted) return;
    Navigator.of(context).pop();
  }
}
''';
        expect(await run(src), isEmpty);
      },
    );
  });
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
        'presentation': LayerConfig(paths: ['lib/src/presentation/']),
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
    coverage: const CoverageConfig(thresholds: {'presentation': 70}),
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
        'presentation': ['presentation'],
      },
    ),
    analyzers: const AnalyzersConfig(),
  );
}
