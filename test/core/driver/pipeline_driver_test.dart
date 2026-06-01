import 'dart:io';
import 'package:alea_flow/src/core/driver/pipeline_driver.dart';
import 'package:alea_flow/alea_flow.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

ProjectConfig _config() => ProjectConfig(
  configVersion: '1.0.0',
  project: const ProjectInfo(packageName: 'demo', pubspecPath: 'pubspec.yaml'),
  architecture: const ArchitectureConfig(
    layers: {
      'domain': LayerConfig(paths: ['lib/src/domain/']),
      'presentation': LayerConfig(
        paths: ['lib/src/presentation/'],
        mayImport: ['domain'],
      ),
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
    modesAvailable: ['guided', 'semi', 'auto'],
    costWarnUsd: 3,
    costHardStopUsd: 5,
    unreliableThreshold: UnreliableThresholdConfig(
      runsWindow: 5,
      badRunsRequired: 3,
      manualCorrectionsPerRun: 5,
    ),
  ),
  gates: const GatesConfig(perLayer: {}),
  analyzers: const AnalyzersConfig(),
);

void main() {
  group('decideRun — phase detection (no gates)', () {
    late Directory tmp;
    late String runDir;
    setUp(() {
      tmp = Directory.systemTemp.createTempSync('alea_drv_');
      runDir = p.join(tmp.path, '.pipeline/runs/DEV-1');
      Directory(runDir).createSync(recursive: true);
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    void writeArtifact(String name, String json) =>
        File(p.join(runDir, name)).writeAsStringSync(json);

    RunDecision decide({String mode = 'auto'}) => decideRun(
      ticketId: 'DEV-1',
      runDir: runDir,
      config: _config(),
      projectRoot: tmp.path,
      schemasDir: 'contracts/schemas',
      requestedMode: mode,
      runGates: false,
    );

    test('empty run dir → next is analyze', () {
      final d = decide();
      expect(d.completedPhase, isNull);
      expect(d.nextAction!.phase, 'analyze');
    });

    test('guided mode → next_action requiresApproval is true', () {
      final d = decide(mode: 'guided');
      expect(d.nextAction!.requiresApproval, isTrue);
    });

    test('auto mode → next_action requiresApproval is false', () {
      final d = decide(mode: 'auto');
      expect(d.nextAction!.requiresApproval, isFalse);
    });

    test('analysis.json present → next is design', () {
      writeArtifact('analysis.json', '{"type":"feature"}');
      final d = decide();
      expect(d.completedPhase, 'analyze');
      expect(d.nextAction!.phase, 'design');
    });

    test('spec approved:true → next is implement-<first layer>', () {
      writeArtifact('analysis.json', '{"type":"feature"}');
      writeArtifact('spec.json', '{"approved":true}');
      final d = decide();
      expect(d.nextAction!.phase, 'implement-domain');
      expect(d.nextAction!.produces, contains('domain_impl.md'));
    });

    test('first-layer impl present → advance to next layer (not done yet)', () {
      writeArtifact('analysis.json', '{"type":"feature"}');
      writeArtifact('spec.json', '{"approved":true}');
      writeArtifact('domain_impl.md', '## files_changed\n');
      final d = decide();
      // config has domain + presentation; domain done → must advance to presentation
      expect(d.status, DriverStatus.advance);
      expect(d.nextAction!.command, contains('implement-presentation'));
      expect(d.completedPhase, 'implement-domain');
    });

    test('all layers impl present → done', () {
      writeArtifact('analysis.json', '{"type":"feature"}');
      writeArtifact('spec.json', '{"approved":true}');
      writeArtifact('domain_impl.md', '## files_changed\n');
      writeArtifact('presentation_impl.md', '## files_changed\n');
      final d = decide();
      expect(d.status, DriverStatus.done);
      expect(d.reason, contains('all layers implemented'));
    });
  });

  group('decideRun — multi-layer feature (3 layers)', () {
    late Directory tmp;
    late String runDir;

    ProjectConfig config3Layers() => ProjectConfig(
      configVersion: '1.0.0',
      project: const ProjectInfo(
        packageName: 'demo',
        pubspecPath: 'pubspec.yaml',
      ),
      architecture: const ArchitectureConfig(
        layers: {
          'domain': LayerConfig(paths: ['lib/src/domain/']),
          'infrastructure': LayerConfig(
            paths: ['lib/src/infrastructure/'],
            mayImport: ['domain'],
          ),
          'presentation': LayerConfig(
            paths: ['lib/src/presentation/'],
            mayImport: ['domain', 'infrastructure'],
          ),
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
        modesAvailable: ['guided', 'semi', 'auto'],
        costWarnUsd: 3,
        costHardStopUsd: 5,
        unreliableThreshold: UnreliableThresholdConfig(
          runsWindow: 5,
          badRunsRequired: 3,
          manualCorrectionsPerRun: 5,
        ),
      ),
      gates: const GatesConfig(perLayer: {}),
      analyzers: const AnalyzersConfig(),
    );

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('alea_drv3_');
      runDir = p.join(tmp.path, '.pipeline/runs/DEV-1');
      Directory(runDir).createSync(recursive: true);
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    void writeArtifact(String name, String json) =>
        File(p.join(runDir, name)).writeAsStringSync(json);

    RunDecision decide3({String mode = 'auto'}) => decideRun(
      ticketId: 'DEV-1',
      runDir: runDir,
      config: config3Layers(),
      projectRoot: tmp.path,
      schemasDir: 'contracts/schemas',
      requestedMode: mode,
      runGates: false,
    );

    test('advances to infrastructure after domain impl exists', () {
      writeArtifact('analysis.json', '{"type":"feature"}');
      writeArtifact('spec.json', '{"approved":true}');
      writeArtifact('domain_impl.md', '## files_changed\n');
      final d = decide3();
      expect(d.status, DriverStatus.advance);
      expect(d.nextAction!.command, '/implement-infrastructure DEV-1');
      expect(d.completedPhase, 'implement-domain');
    });

    test('advances to presentation after domain+infrastructure impl exist', () {
      writeArtifact('analysis.json', '{"type":"feature"}');
      writeArtifact('spec.json', '{"approved":true}');
      writeArtifact('domain_impl.md', '## files_changed\n');
      writeArtifact('infrastructure_impl.md', '## files_changed\n');
      final d = decide3();
      expect(d.status, DriverStatus.advance);
      expect(d.nextAction!.command, '/implement-presentation DEV-1');
      expect(d.completedPhase, 'implement-infrastructure');
    });

    test('done only after ALL layers implemented', () {
      writeArtifact('analysis.json', '{"type":"feature"}');
      writeArtifact('spec.json', '{"approved":true}');
      writeArtifact('domain_impl.md', '## files_changed\n');
      writeArtifact('infrastructure_impl.md', '## files_changed\n');
      writeArtifact('presentation_impl.md', '## files_changed\n');
      final d = decide3();
      expect(d.status, DriverStatus.done);
      expect(d.reason, contains('all layers implemented'));
    });
  });

  group('decideRun — gates', () {
    late Directory tmp;
    late String runDir;
    final schemasDir = p.join(Directory.current.path, 'contracts/schemas');
    void git(List<String> a) => Process.runSync('git', ['-C', tmp.path, ...a]);
    setUp(() {
      tmp = Directory.systemTemp.createTempSync('alea_drvg_');
      runDir = p.join(tmp.path, '.pipeline/runs/DEV-1');
      Directory(runDir).createSync(recursive: true);
    });
    tearDown(() => tmp.deleteSync(recursive: true));
    void wr(String n, String c) => File(p.join(runDir, n)).writeAsStringSync(c);
    RunDecision decide({String mode = 'auto'}) => decideRun(
      ticketId: 'DEV-1',
      runDir: runDir,
      config: _config(),
      projectRoot: tmp.path,
      schemasDir: schemasDir,
      requestedMode: mode,
    );

    test('invalid analysis.json → BLOCKED with violations', () {
      wr('analysis.json', '{"type":"banana"}');
      final d = decide();
      expect(d.status, DriverStatus.blocked);
      expect(d.gate.passed, isFalse);
      expect(d.gate.violations, isNotEmpty);
    });

    test('valid analysis.json → advance to design', () {
      wr('analysis.json', _validAnalysis());
      final d = decide();
      expect(d.status, DriverStatus.advance);
      expect(d.nextAction!.phase, 'design');
    });

    test('implement gate: undeclared changed file → BLOCKED', () {
      wr('analysis.json', _validAnalysis());
      wr('spec.json', '{"approved":true}');
      wr('domain_impl.md', '## files_changed\nlib/a.dart\n');
      git(['init']);
      git(['config', 'user.email', 't@e.com']);
      git(['config', 'user.name', 'T']);
      File(p.join(tmp.path, 'lib/a.dart'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('A');
      git(['add', '.']);
      git(['commit', '-m', 'base']);
      File(p.join(tmp.path, 'lib/a.dart')).writeAsStringSync('A2');
      File(p.join(tmp.path, 'lib/b.dart')).writeAsStringSync('B');
      final d = decide();
      expect(d.status, DriverStatus.blocked);
      expect(d.gate.violations.join(), contains('lib/b.dart'));
    });
  });

  group('decideRun — Gate-0, modes, cost', () {
    late Directory tmp;
    late String runDir;
    final schemasDir = p.join(Directory.current.path, 'contracts/schemas');
    setUp(() {
      tmp = Directory.systemTemp.createTempSync('alea_drvm_');
      runDir = p.join(tmp.path, '.pipeline/runs/DEV-1');
      Directory(runDir).createSync(recursive: true);
      File(p.join(runDir, 'analysis.json')).writeAsStringSync(_validAnalysis());
      File(p.join(runDir, 'spec.json')).writeAsStringSync('{"approved":false}');
    });
    tearDown(() => tmp.deleteSync(recursive: true));
    RunDecision decide(String mode) => decideRun(
      ticketId: 'DEV-1',
      runDir: runDir,
      config: _config(),
      projectRoot: tmp.path,
      schemasDir: schemasDir,
      requestedMode: mode,
    );

    test('guided + spec approved:false → awaitingHuman', () {
      final d = decide('guided');
      expect(d.status, DriverStatus.awaitingHuman);
    });
    test('auto + spec approved:false → advances (Gate-0 skipped)', () {
      final d = decide('auto');
      expect(d.status, DriverStatus.advance);
      expect(d.nextAction!.phase, 'implement-domain');
    });
    test('cost over hard-stop → BLOCKED cost_limit', () {
      File(
        p.join(runDir, 'metrics.json'),
      ).writeAsStringSync('{"estimated_cost_usd": 9.0}');
      final d = decide('auto');
      expect(d.status, DriverStatus.blocked);
      expect(d.reason, contains('cost'));
    });
    test('unreliable history forces guided', () {
      final mdir = Directory(p.join(tmp.path, '.pipeline/metrics'))
        ..createSync(recursive: true);
      File(p.join(mdir.path, 'history.jsonl')).writeAsStringSync(
        '{"manual_code_corrections":9}\n{"manual_code_corrections":9}\n{"manual_code_corrections":9}\n',
      );
      final d = decide('auto');
      expect(d.mode, 'guided');
      expect(d.status, DriverStatus.awaitingHuman);
    });
  });

  group('decideRun — bugfix', () {
    late Directory tmp;
    late String runDir;
    setUp(() {
      tmp = Directory.systemTemp.createTempSync('alea_drvbf_');
      runDir = p.join(tmp.path, '.pipeline/runs/DEV-1');
      Directory(runDir).createSync(recursive: true);
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    void writeArtifact(String name, String content) =>
        File(p.join(runDir, name)).writeAsStringSync(content);

    RunDecision decide({String mode = 'auto'}) => decideRun(
      ticketId: 'DEV-1',
      runDir: runDir,
      config: _config(),
      projectRoot: tmp.path,
      schemasDir: 'contracts/schemas',
      requestedMode: mode,
      runGates: false,
    );

    test('guided: bugfix without approval awaits human (Gate-0)', () {
      writeArtifact('analysis.json', _validBugfixAnalysis());
      final d = decide(mode: 'guided');
      expect(d.status, DriverStatus.awaitingHuman);
      expect(d.reason, contains('analysis.json::approved'));
    });

    test('approved bugfix advances to implement-bugfix', () {
      writeArtifact('analysis.json', _validBugfixAnalysis(approved: true));
      final d = decide(mode: 'guided');
      expect(d.status, DriverStatus.advance);
      expect(d.nextAction!.command, '/implement-bugfix DEV-1');
      expect(d.nextAction!.produces, contains('implementation.md'));
    });

    test('bugfix with implementation.md is done', () {
      writeArtifact('analysis.json', _validBugfixAnalysis(approved: true));
      writeArtifact('implementation.md', '## files_changed\n');
      final d = decide(mode: 'auto');
      expect(d.status, DriverStatus.done);
      expect(d.reason, contains('bugfix implemented'));
    });

    test('auto: bugfix without approval skips Gate-0 and advances', () {
      writeArtifact('analysis.json', _validBugfixAnalysis());
      final d = decide(mode: 'auto');
      expect(d.status, DriverStatus.advance);
      expect(d.nextAction!.command, '/implement-bugfix DEV-1');
    });
  });

  group('decideRun — hard gate on unparseable schema blocks (regression)', () {
    test(
      'a hard gate whose schema cannot be parsed BLOCKS (not advisory-pass)',
      () {
        final tmp = Directory.systemTemp.createTempSync('alea_drvbad_');
        addTearDown(() => tmp.deleteSync(recursive: true));
        final runDir = p.join(tmp.path, '.pipeline/runs/DEV-1');
        Directory(runDir).createSync(recursive: true);
        File(
          p.join(runDir, 'analysis.json'),
        ).writeAsStringSync(_validAnalysis());
        // A schemas dir whose analysis schema is broken YAML.
        final badSchemas = Directory(p.join(tmp.path, 'schemas'))..createSync();
        File(
          p.join(badSchemas.path, 'analysis.schema.yaml'),
        ).writeAsStringSync('this: is: not: valid: yaml:\n  - [unclosed\n');
        final d = decideRun(
          ticketId: 'DEV-1',
          runDir: runDir,
          config: _config(),
          projectRoot: tmp.path,
          schemasDir: badSchemas.path,
          requestedMode: 'auto',
        );
        expect(d.status, DriverStatus.blocked);
        expect(d.gate.passed, isFalse);
        expect(d.gate.violations.join(), contains('could not be parsed'));
      },
    );
  });
}

String _validAnalysis() => '''
{"ticket_id":"DEV-1","type":"feature","title":"t","description":"d desc long",
 "success_criteria":["c1"],"created_at":"2026-05-28T10:00:00Z",
 "feature_description":"f","new_components":{"entities":["E"]}}''';

String _validBugfixAnalysis({bool? approved}) {
  final approvedField = approved == null ? '' : ',"approved":$approved';
  return '{"ticket_id":"DEV-1","type":"bugfix","title":"t",'
      '"description":"d desc long","success_criteria":["c1"],'
      '"created_at":"2026-05-28T10:00:00Z"$approvedField}';
}
