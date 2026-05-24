// Tests for WiringCohesionAnalyzer.
//
// Strategy: three independent fixture trees model three real-world stacks
// (Riverpod + go_router, Bloc + auto_route, GetX + GetPage). The SAME
// analyzer is invoked against each with a different `architecture.wiring`
// configuration, and all three must report zero issues. A separate negative
// fixture verifies that deleting a registration surfaces a
// `missing_registration` issue with the right ruleId.

import 'dart:io';

import 'package:alea_flow/alea_flow.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('WiringCohesionAnalyzer — cross-stack', () {
    test('Riverpod + go_router: zero issues with full wiring', () async {
      final root = _fixture('riverpod_gorouter');
      final result = await WiringCohesionAnalyzer().analyze(
        _ctx(root, _riverpodGorouterConfig()),
      );
      expect(
        result.issues,
        isEmpty,
        reason:
            'AuthService, AuthRepository, AuthRepositoryImpl, LoginScreen '
            'must all be registered.',
      );
    });

    test('Bloc + auto_route: zero issues with full wiring', () async {
      final root = _fixture('bloc_autoroute');
      final result = await WiringCohesionAnalyzer().analyze(
        _ctx(root, _blocAutorouteConfig()),
      );
      expect(result.issues, isEmpty);
    });

    test('GetX + GetPage: zero issues with full wiring', () async {
      final root = _fixture('getx_getpage');
      final result = await WiringCohesionAnalyzer().analyze(
        _ctx(root, _getxGetpageConfig()),
      );
      expect(result.issues, isEmpty);
    });
  });

  group('WiringCohesionAnalyzer — missing registration', () {
    test('Riverpod: removing AuthService from injector → '
        'missing_registration issue', () async {
      final tmp = _copyFixture('riverpod_gorouter');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final injectorPath = p.join(tmp.path, 'lib/src/injector.dart');
      final original = File(injectorPath).readAsStringSync();
      File(injectorPath).writeAsStringSync(
        original.replaceAll(
          'getIt.registerSingleton<AuthService>(AuthService());',
          '// removed for test',
        ),
      );

      final result = await WiringCohesionAnalyzer().analyze(
        _ctx(tmp.path, _riverpodGorouterConfig()),
      );
      final issue = result.issues.firstWhere(
        (i) =>
            i.ruleId ==
            'wiring_cohesion/service_registration/missing_registration',
      );
      expect(issue.severity, Severity.blocker);
      expect(issue.message, contains('AuthService'));
      expect(issue.suggestedFix, contains('registerSingleton'));
    });

    test('GetX: removing HomeScreen from routes.dart → '
        'missing_registration issue', () async {
      final tmp = _copyFixture('getx_getpage');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final routesPath = p.join(tmp.path, 'lib/src/config/routes.dart');
      final original = File(routesPath).readAsStringSync();
      File(routesPath).writeAsStringSync(
        original.replaceAll(
          'GetPage(name: AppRoutes.home, page: () => const HomeScreen()),',
          '// removed for test',
        ),
      );

      final result = await WiringCohesionAnalyzer().analyze(
        _ctx(tmp.path, _getxGetpageConfig()),
      );
      final issue = result.issues.firstWhere(
        (i) => i.ruleId == 'wiring_cohesion/screen_route/missing_registration',
      );
      expect(issue.severity, Severity.blocker);
      expect(issue.message, contains('HomeScreen'));
    });

    test('missing manifest file → manifest_missing issue', () async {
      final tmp = Directory.systemTemp.createTempSync('alea_wiring_no_man_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final lib = Directory(p.join(tmp.path, 'lib'));
      lib.createSync(recursive: true);
      File(
        p.join(lib.path, 'foo_service.dart'),
      ).writeAsStringSync('class FooService {}');

      final config = _configWith(
        wiring: const WiringConfig(
          rules: [
            WiringRule(
              name: 'service_registration',
              classPattern: '*Service',
              manifestFile: 'lib/src/injector.dart', // does not exist
              registrationCall: 'registerSingleton',
            ),
          ],
        ),
      );

      final result = await WiringCohesionAnalyzer().analyze(
        _ctx(tmp.path, config),
      );
      expect(
        result.issues.single.ruleId,
        'wiring_cohesion/service_registration/manifest_missing',
      );
    });
  });

  group('WiringCohesionAnalyzer — config-driven behavior', () {
    test('null wiring config → analyzer is a no-op', () async {
      final root = _fixture('riverpod_gorouter');
      final result = await WiringCohesionAnalyzer().analyze(
        _ctx(root, _configWith(wiring: null)),
      );
      expect(result.issues, isEmpty);
    });

    test('empty rules list → no-op', () async {
      final root = _fixture('riverpod_gorouter');
      final result = await WiringCohesionAnalyzer().analyze(
        _ctx(root, _configWith(wiring: const WiringConfig())),
      );
      expect(result.issues, isEmpty);
    });

    test(
      'changing registration_call without changing files toggles behaviour',
      () async {
        final root = _fixture('riverpod_gorouter');
        // Pretend the project uses Get.put — the existing injector uses
        // registerSingleton, so AuthService is now "not registered".
        final result = await WiringCohesionAnalyzer().analyze(
          _ctx(
            root,
            _configWith(
              wiring: const WiringConfig(
                rules: [
                  WiringRule(
                    name: 'service_registration',
                    classPattern: '*Service',
                    manifestFile: 'lib/src/injector.dart',
                    registrationCall: 'Get.put',
                  ),
                ],
              ),
            ),
          ),
        );
        expect(
          result.issues
              .where((i) => i.ruleId!.endsWith('/missing_registration'))
              .map((i) => i.message),
          isNotEmpty,
        );
      },
    );

    test('class_pattern wildcards — *Pattern and Pattern* both work', () async {
      final root = _fixture('riverpod_gorouter');
      final result = await WiringCohesionAnalyzer().analyze(
        _ctx(
          root,
          _configWith(
            wiring: const WiringConfig(
              rules: [
                WiringRule(
                  name: 'auth_prefix',
                  classPattern: 'Auth*',
                  manifestFile: 'lib/src/injector.dart',
                  registrationCall: 'registerSingleton',
                ),
              ],
            ),
          ),
        ),
      );
      // AuthService, AuthRepository, AuthRepositoryImpl all start with Auth.
      // The first two are registered; AuthRepositoryImpl is the concrete
      // impl referenced inside registerSingleton<AuthRepository>(...) — so
      // it IS registered too (its identifier appears inside the call).
      expect(result.issues, isEmpty);
    });
  });
}

// ── Helpers ────────────────────────────────────────────────────────────────

String _fixture(String name) => p.normalize(
  p.join(
    Directory.current.path,
    'test/analyzers/wiring_cohesion/fixtures',
    name,
  ),
);

Directory _copyFixture(String name) {
  final src = Directory(_fixture(name));
  final tmp = Directory.systemTemp.createTempSync('alea_wiring_${name}_');
  for (final entity in src.listSync(recursive: true, followLinks: false)) {
    final relative = p.relative(entity.path, from: src.path);
    final dest = p.join(tmp.path, relative);
    if (entity is Directory) {
      Directory(dest).createSync(recursive: true);
    } else if (entity is File) {
      Directory(p.dirname(dest)).createSync(recursive: true);
      File(dest).writeAsStringSync(entity.readAsStringSync());
    }
  }
  return tmp;
}

AnalyzerContext _ctx(String projectRoot, ProjectConfig config) =>
    AnalyzerContext(
      filePaths: const [],
      projectRoot: projectRoot,
      config: config,
    );

ProjectConfig _riverpodGorouterConfig() => _configWith(
  wiring: const WiringConfig(
    rules: [
      WiringRule(
        name: 'service_registration',
        classPattern: '*Service',
        manifestFile: 'lib/src/injector.dart',
        registrationCall: 'registerSingleton',
      ),
      WiringRule(
        name: 'repository_registration',
        classPattern: '*Repository',
        manifestFile: 'lib/src/injector.dart',
        registrationCall: 'registerSingleton',
      ),
      WiringRule(
        name: 'screen_route',
        classPattern: '*Screen',
        manifestFile: 'lib/src/config/routes.dart',
        registrationCall: 'GoRoute',
      ),
    ],
  ),
);

ProjectConfig _blocAutorouteConfig() => _configWith(
  wiring: const WiringConfig(
    rules: [
      WiringRule(
        name: 'service_registration',
        classPattern: '*Service',
        manifestFile: 'lib/src/injector.dart',
        registrationCall: 'registerLazySingleton',
      ),
      WiringRule(
        name: 'screen_route',
        classPattern: '*Screen',
        manifestFile: 'lib/src/config/routes.dart',
        registrationCall: 'AutoRoute',
      ),
    ],
  ),
);

ProjectConfig _getxGetpageConfig() => _configWith(
  wiring: const WiringConfig(
    rules: [
      WiringRule(
        name: 'controller_registration',
        classPattern: '*Controller',
        manifestFile: 'lib/src/injector.dart',
        registrationCall: 'Get.put',
      ),
      WiringRule(
        name: 'screen_route',
        classPattern: '*Screen',
        manifestFile: 'lib/src/config/routes.dart',
        registrationCall: 'GetPage',
      ),
    ],
  ),
);

ProjectConfig _configWith({required WiringConfig? wiring}) => ProjectConfig(
  configVersion: '1.0.0',
  project: const ProjectInfo(
    packageName: 'fixture_pkg',
    pubspecPath: 'pubspec.yaml',
  ),
  architecture: ArchitectureConfig(
    layers: const {
      'package': LayerConfig(paths: ['lib/']),
    },
    wiring: wiring,
  ),
  stateManagement: const StateManagementConfig(style: 'none'),
  routing: const RoutingConfig(package: 'none', routerPath: ''),
  theme: const ThemeConfig(path: ''),
  testing: const TestingConfig(
    framework: 'dart_test',
    fakesPath: 'test/fakes/',
  ),
  coverage: const CoverageConfig(thresholds: {'package': 0}),
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
