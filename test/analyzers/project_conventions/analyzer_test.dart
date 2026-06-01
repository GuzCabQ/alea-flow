// Tests for the project_conventions analyzer.
//
// Rules covered:
//   1. naming_class_case   — class/enum/mixin/extension must be PascalCase.
//   2. naming_method_case  — methods/functions must be lowerCamelCase.
//   3. todo_without_ticket — TODO/FIXME without a ticket reference.
//
// Generated files (.g.dart / .freezed.dart / .mocks.dart) are skipped.

import 'dart:io';

import 'package:alea_flow/alea_flow.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('ProjectConventionsAnalyzer', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('alea_conv_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    // ── helpers ──────────────────────────────────────────────────────────────

    Future<AnalysisResult> runOn(String dartSource, {String? filename}) async {
      final name = filename ?? 'fixture.dart';
      final file = File(p.join(tmp.path, name))..writeAsStringSync(dartSource);
      return ProjectConventionsAnalyzer().analyze(
        AnalyzerContext(
          filePaths: [file.path],
          projectRoot: tmp.path,
          config: _minimalConfig(),
        ),
      );
    }

    // ── clean: all PascalCase types, camelCase methods, no TODO issues ────────

    test('emits no issues for a perfectly-named file', () async {
      const src = '''
class MyWidget {
  void doSomething() {}
  String buildTitle() => 'title';
}
enum MyStatus { active, inactive }
''';
      final result = await runOn(src);
      expect(result.issues, isEmpty);
    });

    // ── naming_class_case violations ─────────────────────────────────────────

    test('flags a snake_case class name', () async {
      const src = 'class my_widget {}\n';
      final result = await runOn(src);
      final naming = result.issues
          .where((i) => i.rule == 'naming_class_case')
          .toList();
      expect(naming, hasLength(1));
      expect(naming.first.ruleId, 'project_conventions/type_pascal_case');
      expect(naming.first.severity, Severity.minor);
      expect(naming.first.line, 1);
    });

    test('flags a lowercase class name', () async {
      const src = 'class mywidget {}\n';
      final result = await runOn(src);
      final naming = result.issues
          .where((i) => i.rule == 'naming_class_case')
          .toList();
      expect(naming, hasLength(1));
    });

    test(
      'private class with underscore prefix still checked after stripping',
      () async {
        // _myWidget stripped → myWidget → starts lowercase → violation
        const src = 'class _myWidget {}\n';
        final result = await runOn(src);
        final naming = result.issues
            .where((i) => i.rule == 'naming_class_case')
            .toList();
        expect(naming, hasLength(1));
      },
    );

    test('private PascalCase class is clean', () async {
      // _MyWidget stripped → MyWidget → PascalCase → ok
      const src = 'class _MyWidget {}\n';
      final result = await runOn(src);
      final naming = result.issues
          .where((i) => i.rule == 'naming_class_case')
          .toList();
      expect(naming, isEmpty);
    });

    test('flags a snake_case enum name', () async {
      const src = 'enum my_status { a, b }\n';
      final result = await runOn(src);
      final naming = result.issues
          .where((i) => i.rule == 'naming_class_case')
          .toList();
      expect(naming, hasLength(1));
    });

    test('PascalCase enum is clean', () async {
      const src = 'enum MyStatus { active, inactive }\n';
      final result = await runOn(src);
      final naming = result.issues
          .where((i) => i.rule == 'naming_class_case')
          .toList();
      expect(naming, isEmpty);
    });

    test('flags a snake_case mixin name', () async {
      const src = 'mixin my_mixin {}\n';
      final result = await runOn(src);
      final naming = result.issues
          .where((i) => i.rule == 'naming_class_case')
          .toList();
      expect(naming, hasLength(1));
    });

    test('flags a named extension with snake_case', () async {
      const src =
          'extension my_ext on String { String get up => toUpperCase(); }\n';
      final result = await runOn(src);
      final naming = result.issues
          .where((i) => i.rule == 'naming_class_case')
          .toList();
      expect(naming, hasLength(1));
    });

    // ── naming_method_case violations ─────────────────────────────────────────

    test('flags a snake_case method name', () async {
      const src = '''
class MyWidget {
  void do_something() {}
}
''';
      final result = await runOn(src);
      final naming = result.issues
          .where((i) => i.rule == 'naming_method_case')
          .toList();
      expect(naming, hasLength(1));
      expect(naming.first.ruleId, 'project_conventions/member_camel_case');
      expect(naming.first.severity, Severity.minor);
    });

    test('flags a snake_case top-level function (not main)', () async {
      const src = 'void my_function() {}\n';
      final result = await runOn(src);
      final naming = result.issues
          .where((i) => i.rule == 'naming_method_case')
          .toList();
      expect(naming, hasLength(1));
    });

    test('does NOT flag the main() function', () async {
      const src = 'void main() {}\n';
      final result = await runOn(src);
      expect(result.issues, isEmpty);
    });

    test('lowerCamelCase method is clean', () async {
      const src = '''
class MyWidget {
  void doSomething() {}
}
''';
      final result = await runOn(src);
      final naming = result.issues
          .where((i) => i.rule == 'naming_method_case')
          .toList();
      expect(naming, isEmpty);
    });

    // ── todo_without_ticket violations ────────────────────────────────────────

    test('flags // TODO without ticket reference', () async {
      const src = '''
class MyWidget {
  // TODO: fix this later
  void doSomething() {}
}
''';
      final result = await runOn(src);
      final todos = result.issues
          .where((i) => i.rule == 'todo_without_ticket')
          .toList();
      expect(todos, hasLength(1));
      expect(todos.first.ruleId, 'project_conventions/todo_no_ticket');
      expect(todos.first.severity, Severity.minor);
      expect(todos.first.line, 2);
    });

    test('flags // FIXME without ticket reference', () async {
      const src = '''
// FIXME: broken behavior
void doSomething() {}
''';
      final result = await runOn(src);
      final todos = result.issues
          .where((i) => i.rule == 'todo_without_ticket')
          .toList();
      expect(todos, hasLength(1));
    });

    test('does NOT flag // TODO with DEV- ticket', () async {
      const src = '''
// TODO(DEV-1234): fix this properly
void doSomething() {}
''';
      final result = await runOn(src);
      final todos = result.issues
          .where((i) => i.rule == 'todo_without_ticket')
          .toList();
      expect(todos, isEmpty);
    });

    test('does NOT flag // TODO with #N ticket', () async {
      const src = '''
// TODO(#42): add test coverage
void doSomething() {}
''';
      final result = await runOn(src);
      final todos = result.issues
          .where((i) => i.rule == 'todo_without_ticket')
          .toList();
      expect(todos, isEmpty);
    });

    test('does NOT flag // TODO with GH- ticket', () async {
      const src = '''
// TODO(GH-99): address upstream bug
void main() {}
''';
      final result = await runOn(src);
      final todos = result.issues
          .where((i) => i.rule == 'todo_without_ticket')
          .toList();
      expect(todos, isEmpty);
    });

    // ── generated files are skipped ───────────────────────────────────────────

    test('skips .g.dart files entirely', () async {
      // A .g.dart file with a snake_case class and a TODO without ticket.
      const src = '''
// TODO: no ticket
class bad_generated_class {}
''';
      final result = await runOn(src, filename: 'fixture.g.dart');
      expect(result.issues, isEmpty);
    });

    test('skips .freezed.dart files', () async {
      const src = 'class bad_name {}\n';
      final result = await runOn(src, filename: 'fixture.freezed.dart');
      expect(result.issues, isEmpty);
    });

    test('skips .mocks.dart files', () async {
      const src = '''
// TODO: no ticket here either
class bad_mock {}
''';
      final result = await runOn(src, filename: 'fixture.mocks.dart');
      expect(result.issues, isEmpty);
    });

    // ── operator methods are exempt from camelCase check ─────────────────────

    test('does NOT flag operator methods', () async {
      const src = '''
class MyClass {
  bool operator ==(Object other) => identical(this, other);
  int operator +(MyClass other) => 0;
}
''';
      final result = await runOn(src);
      final naming = result.issues
          .where((i) => i.rule == 'naming_method_case')
          .toList();
      expect(naming, isEmpty);
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
