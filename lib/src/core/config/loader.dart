// ALEA — `.alea.yaml` loader.
//
// Parses a consumer's `.alea.yaml` into a [ProjectConfig]. This is the only
// place YAML→Dart translation happens; every other module consumes the
// resulting object.
//
// The loader is intentionally lenient on unknown fields (forward compat:
// adding a new field to the schema must NOT break consumers using older
// loaders). It is strict on missing required fields and on type mismatches —
// those throw [ProjectConfigException] with a path to the offending field.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../../contracts/project_config.dart';

/// Load and parse `<projectRoot>/.alea.yaml`.
ProjectConfig loadProjectConfig(String projectRoot) {
  final aleaPath = p.join(projectRoot, '.alea.yaml');
  final file = File(aleaPath);
  if (!file.existsSync()) {
    throw ProjectConfigException(
      '.alea.yaml not found at $aleaPath',
      field: '.alea.yaml',
    );
  }
  return parseProjectConfigYaml(file.readAsStringSync());
}

/// Parse a YAML string directly into a [ProjectConfig]. Useful for tests.
ProjectConfig parseProjectConfigYaml(String yamlString) {
  final root = loadYaml(yamlString);
  if (root is! YamlMap) {
    throw const ProjectConfigException('Top-level must be a YAML map');
  }
  return _parseRoot(root);
}

// ── Top-level ───────────────────────────────────────────────────────────────

ProjectConfig _parseRoot(YamlMap y) {
  return ProjectConfig(
    configVersion: _requireString(y, 'config_version'),
    project: _parseProject(_requireMap(y, 'project')),
    architecture: _parseArchitecture(_requireMap(y, 'architecture')),
    stateManagement: _parseStateMgmt(_requireMap(y, 'state_management')),
    routing: _parseRouting(_requireMap(y, 'routing')),
    theme: _parseTheme(_requireMap(y, 'theme')),
    testing: _parseTesting(_requireMap(y, 'testing')),
    coverage: _parseCoverage(_requireMap(y, 'coverage')),
    ticketSource: _parseTicketSource(_requireMap(y, 'ticket_source')),
    designSource: _parseDesignSource(_requireMap(y, 'design_source')),
    mr: _parseMr(_requireMap(y, 'mr')),
    pipeline: _parsePipeline(_requireMap(y, 'pipeline')),
    gates: _parseGates(_requireMap(y, 'gates')),
    analyzers: _parseAnalyzers(y['analyzers']),
    docs: _parseStringMap(y['docs']),
  );
}

ProjectInfo _parseProject(YamlMap y) => ProjectInfo(
  packageName: _requireString(y, 'package_name'),
  pubspecPath: _stringOr(y, 'pubspec_path', 'pubspec.yaml'),
  displayName: _stringOrNull(y, 'display_name'),
);

ArchitectureConfig _parseArchitecture(YamlMap y) {
  final layersRaw = _requireMap(y, 'layers');
  final layers = <String, LayerConfig>{};
  for (final entry in layersRaw.entries) {
    final name = entry.key.toString();
    final v = entry.value;
    if (v is! YamlMap) {
      throw ProjectConfigException(
        'architecture.layers.$name must be a map',
        field: 'architecture.layers.$name',
      );
    }
    layers[name] = LayerConfig(
      paths: _requireStringList(v, 'paths'),
      mayImport: _stringList(v, 'may_import'),
      forbidImports: _stringList(v, 'forbid_imports'),
    );
  }
  if (layers.isEmpty) {
    throw const ProjectConfigException(
      'architecture.layers must contain at least one layer',
      field: 'architecture.layers',
    );
  }
  return ArchitectureConfig(
    layers: layers,
    packageBoundaries: _parsePackageBoundaries(y['package_boundaries']),
    wiring: _parseWiring(y['wiring']),
  );
}

WiringConfig? _parseWiring(Object? raw) {
  if (raw == null) return null;
  if (raw is! YamlMap) {
    throw const ProjectConfigException(
      'architecture.wiring must be a map',
      field: 'architecture.wiring',
    );
  }
  final rulesRaw = raw['rules'];
  if (rulesRaw == null) return const WiringConfig();
  if (rulesRaw is! YamlList) {
    throw const ProjectConfigException(
      'architecture.wiring.rules must be a list',
      field: 'architecture.wiring.rules',
    );
  }
  final rules = <WiringRule>[];
  for (var i = 0; i < rulesRaw.length; i++) {
    final item = rulesRaw[i];
    if (item is! YamlMap) {
      throw ProjectConfigException(
        'architecture.wiring.rules[$i] must be a map',
        field: 'architecture.wiring.rules[$i]',
      );
    }
    rules.add(
      WiringRule(
        name: _requireString(item, 'name'),
        classPattern: _requireString(item, 'class_pattern'),
        manifestFile: _requireString(item, 'manifest_file'),
        registrationCall: _requireString(item, 'registration_call'),
        scanPaths: _stringList(item, 'scan_paths'),
      ),
    );
  }
  return WiringConfig(rules: List.unmodifiable(rules));
}

List<PackageBoundary> _parsePackageBoundaries(Object? raw) {
  if (raw == null) return const [];
  if (raw is! YamlList) {
    throw const ProjectConfigException(
      'architecture.package_boundaries must be a list',
      field: 'architecture.package_boundaries',
    );
  }
  final result = <PackageBoundary>[];
  for (var i = 0; i < raw.length; i++) {
    final item = raw[i];
    if (item is! YamlMap) {
      throw ProjectConfigException(
        'architecture.package_boundaries[$i] must be a map',
        field: 'architecture.package_boundaries[$i]',
      );
    }
    final name = _requireString(item, 'name');
    result.add(
      PackageBoundary(
        name: name,
        description: _stringOrNull(item, 'description'),
        appliesTo: _requireStringList(item, 'applies_to'),
        forbid: _requireStringList(item, 'forbid'),
      ),
    );
  }
  return List.unmodifiable(result);
}

StateManagementConfig _parseStateMgmt(YamlMap y) {
  final rulesRaw = y['rules'];
  return StateManagementConfig(
    style: _requireString(y, 'style'),
    rules: rulesRaw is YamlMap
        ? Map<String, Object?>.fromEntries(
            rulesRaw.entries.map((e) => MapEntry(e.key.toString(), e.value)),
          )
        : const {},
  );
}

RoutingConfig _parseRouting(YamlMap y) => RoutingConfig(
  package: _requireString(y, 'package'),
  routerPath: _requireString(y, 'router_path'),
);

ThemeConfig _parseTheme(YamlMap y) => ThemeConfig(
  path: _requireString(y, 'path'),
  brandColors: _parseStringMap(y['brand_colors']),
  typography: _parseStringMap(y['typography']),
  tokenCatalog: _parseTokenCatalog(y['token_catalog']),
);

TokenCatalogConfig? _parseTokenCatalog(Object? raw) {
  if (raw == null) return null;
  if (raw is! YamlMap) {
    throw const ProjectConfigException(
      'theme.token_catalog must be a map',
      field: 'theme.token_catalog',
    );
  }
  final conventionsRaw = raw['conventions'];
  return TokenCatalogConfig(
    adapter: _requireString(raw, 'adapter'),
    source: _requireString(raw, 'source'),
    conventions: conventionsRaw is YamlMap
        ? Map<String, Object?>.fromEntries(
            conventionsRaw.entries.map(
              (e) => MapEntry(e.key.toString(), e.value),
            ),
          )
        : const {},
  );
}

TestingConfig _parseTesting(YamlMap y) => TestingConfig(
  framework: _stringOr(y, 'framework', 'flutter_test'),
  fakesPath: _stringOr(y, 'fakes_path', 'test/fakes/'),
  pattern: _stringOr(y, 'pattern', 'aaa'),
  overrideTarget: _stringOr(y, 'override_target', 'repository'),
  preferFakesOverMocks: _boolOr(y, 'prefer_fakes_over_mocks', true),
  fakeClassPattern: _stringOr(y, 'fake_class_pattern', 'Fake{Name}Repository'),
);

CoverageConfig _parseCoverage(YamlMap y) {
  final thresholdsRaw = _requireMap(y, 'thresholds');
  final thresholds = <String, int>{};
  for (final entry in thresholdsRaw.entries) {
    final v = entry.value;
    if (v is! int) {
      throw ProjectConfigException(
        'coverage.thresholds.${entry.key} must be an integer',
        field: 'coverage.thresholds.${entry.key}',
      );
    }
    thresholds[entry.key.toString()] = v;
  }
  return CoverageConfig(thresholds: thresholds);
}

TicketSourceConfig _parseTicketSource(YamlMap y) {
  final cfgRaw = y['config'];
  return TicketSourceConfig(
    adapter: _requireString(y, 'adapter'),
    config: cfgRaw is YamlMap
        ? Map<String, Object?>.fromEntries(
            cfgRaw.entries.map((e) => MapEntry(e.key.toString(), e.value)),
          )
        : const {},
  );
}

DesignSourceConfig _parseDesignSource(YamlMap y) {
  final adaptersRaw = y['adapters'];
  final adapters = <String, DesignAdapterConfig>{};
  if (adaptersRaw is YamlMap) {
    for (final entry in adaptersRaw.entries) {
      final v = entry.value;
      if (v is! YamlMap) continue;
      adapters[entry.key.toString()] = DesignAdapterConfig(
        enabled: _boolOr(v, 'enabled', false),
        options: Map<String, Object?>.fromEntries(
          v.entries
              .where((e) => e.key != 'enabled')
              .map((e) => MapEntry(e.key.toString(), e.value)),
        ),
      );
    }
  }
  return DesignSourceConfig(
    defaultAdapter: _requireString(y, 'default'),
    adapters: adapters,
  );
}

MrConfig _parseMr(YamlMap y) => MrConfig(
  policy: _requireString(y, 'policy'),
  branchPattern: _requireString(y, 'branch_pattern'),
  prePush: _stringList(y, 'pre_push'),
);

PipelineOpsConfig _parsePipeline(YamlMap y) {
  final thresholdRaw = y['unreliable_threshold'];
  final threshold = thresholdRaw is YamlMap
      ? UnreliableThresholdConfig(
          runsWindow: _intOr(thresholdRaw, 'runs_window', 5),
          badRunsRequired: _intOr(thresholdRaw, 'bad_runs_required', 3),
          manualCorrectionsPerRun: _intOr(
            thresholdRaw,
            'manual_corrections_per_run',
            5,
          ),
        )
      : const UnreliableThresholdConfig(
          runsWindow: 5,
          badRunsRequired: 3,
          manualCorrectionsPerRun: 5,
        );
  return PipelineOpsConfig(
    defaultMode: _stringOr(y, 'default_mode', 'guided'),
    modesAvailable: _stringList(y, 'modes_available').isEmpty
        ? const ['guided', 'semi', 'auto']
        : _stringList(y, 'modes_available'),
    costWarnUsd: _doubleOr(y, 'cost_warn_usd', 3.0),
    costHardStopUsd: _doubleOr(y, 'cost_hard_stop_usd', 5.0),
    unreliableThreshold: threshold,
  );
}

GatesConfig _parseGates(YamlMap y) {
  final perLayer = <String, List<String>>{};
  for (final entry in y.entries) {
    final v = entry.value;
    if (v is YamlList) {
      perLayer[entry.key.toString()] = v
          .map((item) => item.toString())
          .toList(growable: false);
    }
  }
  return GatesConfig(perLayer: perLayer);
}

AnalyzersConfig _parseAnalyzers(Object? raw) {
  if (raw is! YamlMap) return const AnalyzersConfig();
  final enabledRaw = raw['enabled'];
  final overridesRaw = raw['severity_overrides'];
  final optionsRaw = raw['options'];
  return AnalyzersConfig(
    enabled: enabledRaw is YamlList
        ? enabledRaw.map((e) => e.toString()).toList(growable: false)
        : const [],
    severityOverrides: overridesRaw is YamlMap
        ? Map<String, String>.fromEntries(
            overridesRaw.entries.map(
              (e) => MapEntry(e.key.toString(), e.value.toString()),
            ),
          )
        : const {},
    options: optionsRaw is YamlMap
        ? _parseAnalyzerOptions(optionsRaw)
        : const {},
  );
}

Map<String, Map<String, Object?>> _parseAnalyzerOptions(YamlMap raw) {
  final out = <String, Map<String, Object?>>{};
  for (final entry in raw.entries) {
    final v = entry.value;
    if (v is! YamlMap) continue;
    out[entry.key.toString()] = _yamlMapToDart(v);
  }
  return out;
}

/// Convert a YamlMap (which is a `Map<dynamic, dynamic>`) to a Dart-friendly
/// `Map<String, Object?>`, recursing into nested maps and lists.
Map<String, Object?> _yamlMapToDart(YamlMap raw) {
  return Map<String, Object?>.fromEntries(
    raw.entries.map(
      (e) => MapEntry(e.key.toString(), _coerceYamlValue(e.value)),
    ),
  );
}

Object? _coerceYamlValue(Object? v) {
  if (v is YamlMap) return _yamlMapToDart(v);
  if (v is YamlList) return v.map(_coerceYamlValue).toList(growable: false);
  return v;
}

// ── Primitive helpers ──────────────────────────────────────────────────────

YamlMap _requireMap(YamlMap y, String key) {
  final v = y[key];
  if (v is! YamlMap) {
    throw ProjectConfigException(
      v == null ? '$key is required' : '$key must be a map',
      field: key,
    );
  }
  return v;
}

String _requireString(YamlMap y, String key) {
  final v = y[key];
  if (v is! String) {
    throw ProjectConfigException(
      v == null ? '$key is required' : '$key must be a string',
      field: key,
    );
  }
  return v;
}

String _stringOr(YamlMap y, String key, String fallback) {
  final v = y[key];
  return v is String ? v : fallback;
}

String? _stringOrNull(YamlMap y, String key) {
  final v = y[key];
  return v is String ? v : null;
}

int _intOr(YamlMap y, String key, int fallback) {
  final v = y[key];
  return v is int ? v : fallback;
}

double _doubleOr(YamlMap y, String key, double fallback) {
  final v = y[key];
  if (v is double) return v;
  if (v is int) return v.toDouble();
  return fallback;
}

bool _boolOr(YamlMap y, String key, bool fallback) {
  final v = y[key];
  return v is bool ? v : fallback;
}

List<String> _requireStringList(YamlMap y, String key) {
  final v = y[key];
  if (v is! YamlList) {
    throw ProjectConfigException(
      v == null ? '$key is required' : '$key must be a list',
      field: key,
    );
  }
  return v.map((e) => e.toString()).toList(growable: false);
}

List<String> _stringList(YamlMap y, String key) {
  final v = y[key];
  if (v is! YamlList) return const [];
  return v.map((e) => e.toString()).toList(growable: false);
}

Map<String, String> _parseStringMap(Object? raw) {
  if (raw is! YamlMap) return const {};
  return Map<String, String>.fromEntries(
    raw.entries.map((e) => MapEntry(e.key.toString(), e.value.toString())),
  );
}
