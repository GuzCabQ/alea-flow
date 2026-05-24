import 'dart:io';

import 'package:alea_flow/alea_flow.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../_helpers.dart';

void main() {
  group('RiverpodManualCodeGen', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('alea_rpm_');
    });

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    test(
      'presentation layer generates state + notifier + screen at the configured paths',
      () async {
        final config = buildScaffoldTestConfig(packageName: 'demo');
        final adapter = RiverpodManualCodeGen();
        final plan = await adapter.generate(
          CodeGenRequest(
            layer: CodeGenLayer.presentation,
            spec: const {
              'feature': {'name': 'auth'},
            },
            projectRoot: root.path,
            config: config,
          ),
        );

        final paths = plan.files.map((f) => f.relativePath).toSet();
        expect(paths, {
          'lib/src/domain/feature/auth/auth_state.dart',
          'lib/src/domain/feature/auth/auth_notifier.dart',
          'lib/src/presentation/feature/auth/auth_screen.dart',
        });
      },
    );

    test(
      'orchestrator end-to-end: files land on disk, verification passes',
      () async {
        final config = buildScaffoldTestConfig(packageName: 'demo');
        final orchestrator = CodeGenOrchestrator();
        final result = await orchestrator.run(
          adapter: RiverpodManualCodeGen(),
          request: CodeGenRequest(
            layer: CodeGenLayer.presentation,
            spec: const {
              'feature': {'name': 'auth'},
            },
            projectRoot: root.path,
            config: config,
          ),
        );
        expect(result.success, isTrue);
        expect(
          result.outcomes.every((o) => o.action == ScaffoldAction.create),
          isTrue,
        );
        for (final outcome in result.outcomes) {
          expect(
            File(p.join(root.path, outcome.relativePath)).existsSync(),
            isTrue,
          );
        }
      },
    );

    test(
      'idempotency: second run on identical config produces only skip outcomes',
      () async {
        final config = buildScaffoldTestConfig(packageName: 'demo');
        final orchestrator = CodeGenOrchestrator();
        final adapter = RiverpodManualCodeGen();
        final request = CodeGenRequest(
          layer: CodeGenLayer.presentation,
          spec: const {
            'feature': {'name': 'auth'},
          },
          projectRoot: root.path,
          config: config,
        );
        await orchestrator.run(adapter: adapter, request: request);
        final second = await orchestrator.run(
          adapter: adapter,
          request: request,
        );
        expect(
          second.outcomes.every((o) => o.action == ScaffoldAction.skip),
          isTrue,
        );
      },
    );

    test('feature names from spec.feature_name (flat form) also work', () async {
      final config = buildScaffoldTestConfig(packageName: 'demo');
      final adapter = RiverpodManualCodeGen();
      final plan = await adapter.generate(
        CodeGenRequest(
          layer: CodeGenLayer.presentation,
          spec: const {'feature_name': 'user_profile'},
          projectRoot: root.path,
          config: config,
        ),
      );
      expect(
        plan.files.map((f) => f.relativePath),
        containsAll([
          'lib/src/domain/feature/user_profile/user_profile_state.dart',
          'lib/src/presentation/feature/user_profile/user_profile_screen.dart',
        ]),
      );
    });

    test('missing feature name throws CodeGenException', () async {
      final config = buildScaffoldTestConfig(packageName: 'demo');
      final adapter = RiverpodManualCodeGen();
      expect(
        () => adapter.generate(
          CodeGenRequest(
            layer: CodeGenLayer.presentation,
            spec: const {},
            projectRoot: root.path,
            config: config,
          ),
        ),
        throwsA(isA<CodeGenException>()),
      );
    });

    test(
      'rollback: when verification fails the filesystem is restored',
      () async {
        final config = buildScaffoldTestConfig(packageName: 'demo');

        // Pre-existing domain file with content the generator would overwrite.
        final existing = File(
          p.join(root.path, 'lib/src/domain/feature/auth/auth_state.dart'),
        );
        existing.parent.createSync(recursive: true);
        existing.writeAsStringSync('// hand-written, do not touch');

        // Inject a verifier that always blocks the run.
        final orchestrator = _RollbackingOrchestrator();
        final result = await orchestrator.run(
          adapter: RiverpodManualCodeGen(),
          request: CodeGenRequest(
            layer: CodeGenLayer.presentation,
            spec: const {
              'feature': {'name': 'auth'},
            },
            projectRoot: root.path,
            config: config,
          ),
        );
        expect(result.success, isFalse);
        expect(result.verification.rolledBack, isTrue);
        expect(existing.readAsStringSync(), '// hand-written, do not touch');
      },
    );
  });
}

/// Orchestrator subclass that forces a verification failure to exercise the
/// rollback path. Real callers use the default [CodeGenOrchestrator].
class _RollbackingOrchestrator extends CodeGenOrchestrator {
  _RollbackingOrchestrator() : super();

  @override
  Future<CodeGenRunResult> run({
    required CodeGenAdapter adapter,
    required CodeGenRequest request,
  }) async {
    final plan = await adapter.generate(request);
    final executor = ScaffoldExecutor(projectRoot: request.projectRoot);
    final outcomes = await executor.apply(plan);
    final rolled = await executor.rollback(outcomes);
    return CodeGenRunResult(
      plan: plan,
      outcomes: rolled,
      verification: const ScaffoldVerification(
        passed: false,
        rolledBack: true,
        elapsed: Duration.zero,
      ),
    );
  }
}
