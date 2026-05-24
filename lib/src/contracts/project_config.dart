// ALEA — Parsed `.alea.yaml` shape.
//
// Every module reads from a single [ProjectConfig] instance loaded once at the start
// of every `/pipeline` invocation. The YAML form is validated against
// `contracts/schemas/project-config.schema.yaml`; this Dart class is the in-memory
// representation produced by `core/commands/pipeline` (or any consumer that wants to
// invoke individual modules programmatically).
//
// Design notes:
//   - Every field is nullable or has a default. Validation against the schema happens
//     at parse time; once a ProjectConfig exists, modules treat its values as trusted.
//   - The shape mirrors the YAML 1:1 to minimize translation surface. If a field is
//     in the schema, it's a field here.
//   - Nested objects are small immutable classes, not Maps. Maps are reserved for
//     open-ended sections like `analyzers.severity_overrides`.

class ProjectConfig {
  final String configVersion;
  final ProjectInfo project;
  final ArchitectureConfig architecture;
  final StateManagementConfig stateManagement;
  final RoutingConfig routing;
  final ThemeConfig theme;
  final TestingConfig testing;
  final CoverageConfig coverage;
  final TicketSourceConfig ticketSource;
  final DesignSourceConfig designSource;
  final MrConfig mr;
  final PipelineOpsConfig pipeline;
  final GatesConfig gates;
  final AnalyzersConfig analyzers;
  final Map<String, String> docs;

  const ProjectConfig({
    required this.configVersion,
    required this.project,
    required this.architecture,
    required this.stateManagement,
    required this.routing,
    required this.theme,
    required this.testing,
    required this.coverage,
    required this.ticketSource,
    required this.designSource,
    required this.mr,
    required this.pipeline,
    required this.gates,
    required this.analyzers,
    this.docs = const {},
  });

  /// Parse from raw YAML (already parsed to Map by the caller).
  /// Throws [ProjectConfigException] when required fields are missing or
  /// when validation against `project-config.schema.yaml` fails.
  ///
  /// Implementation goes in `core/config/loader.dart` (TBD in step 5).
  static ProjectConfig fromYaml(Map<String, Object?> yaml) {
    throw UnimplementedError('Implemented in core/config/loader.dart');
  }
}

class ProjectInfo {
  final String packageName;
  final String pubspecPath;
  final String? displayName;

  const ProjectInfo({
    required this.packageName,
    required this.pubspecPath,
    this.displayName,
  });
}

class ArchitectureConfig {
  final Map<String, LayerConfig> layers;

  /// Optional package-level boundary rules.
  ///
  /// Distinct from [layers]: a layer assigns each file to exactly one bucket
  /// (Clean Architecture). A package boundary is a free-form rule of the form
  /// "files matching X must not import Y" — useful for library packages that
  /// need to enforce purity invariants (e.g. matching/ cannot use dart:io)
  /// orthogonally to app-level layers.
  ///
  /// Defaults to empty: consumers that do not declare boundaries see no
  /// behavior change.
  final List<PackageBoundary> packageBoundaries;

  /// Optional declarative wiring rules consumed by `WiringCohesionAnalyzer`.
  /// Null when the consumer does not opt in.
  final WiringConfig? wiring;

  const ArchitectureConfig({
    required this.layers,
    this.packageBoundaries = const [],
    this.wiring,
  });
}

/// Declarative configuration for the `wiring_cohesion` analyzer.
///
/// The analyzer enforces: "every class whose name matches [WiringRule.classPattern]
/// in the project source must be registered (i.e. referenced inside an
/// invocation of [WiringRule.registrationCall]) in [WiringRule.manifestFile]".
/// One rule covers services, another covers repositories, another covers
/// route registrations — there is no built-in distinction between them.
///
/// Agnostic by design: GetX consumers declare `Get.put`, Riverpod consumers
/// declare `registerSingleton`, Bloc consumers declare `getIt.registerSingleton`,
/// auto_route consumers declare `AutoRoute`, go_router consumers declare
/// `GoRoute`. The analyzer ships no presets.
class WiringConfig {
  final List<WiringRule> rules;
  const WiringConfig({this.rules = const []});
}

class WiringRule {
  /// Stable human-readable label (used in issue ruleIds and messages).
  /// Example: `service_registration`, `screen_route`.
  final String name;

  /// Glob-like pattern matched against class names. Supports `*` at the
  /// start, end, or both. Examples: `*Service`, `Auth*`, `*Repository*`.
  final String classPattern;

  /// Project-relative path of the file expected to contain the registration.
  /// Example: `lib/src/injector.dart`, `lib/src/config/routes.dart`.
  final String manifestFile;

  /// Name of the function/constructor whose invocation registers a class.
  /// Examples:
  ///   - `registerSingleton` (manual DI)
  ///   - `Get.put` (GetX)
  ///   - `registerLazySingleton` (get_it)
  ///   - `GoRoute` (go_router)
  ///   - `AutoRoute` (auto_route)
  ///   - `GetPage` (GetX routes)
  /// The analyzer accepts either a bare method name (`registerSingleton`)
  /// or a dotted target (`Get.put`). Matching is exact, no globs.
  final String registrationCall;

  /// Optional set of directories (project-relative) to scan for candidate
  /// classes. When empty, every path declared in
  /// `architecture.layers.*.paths` is scanned.
  final List<String> scanPaths;

  const WiringRule({
    required this.name,
    required this.classPattern,
    required this.manifestFile,
    required this.registrationCall,
    this.scanPaths = const [],
  });
}

/// A single boundary rule used by `PackageBoundaryAnalyzer`.
///
/// Multiple boundaries can apply to the same file. Each boundary independently
/// emits at most one issue per (file, forbid-prefix) pair. Path patterns and
/// forbid entries are prefix-matched: a `paths` entry `lib/src/contracts/`
/// matches every file under that directory; a `forbid` entry `dart:io` matches
/// the import URI literally; a `forbid` entry `package:foo/src/internal/`
/// matches anything under that package subtree.
class PackageBoundary {
  final String name;
  final String? description;
  final List<String> appliesTo;
  final List<String> forbid;

  const PackageBoundary({
    required this.name,
    this.description,
    required this.appliesTo,
    required this.forbid,
  });
}

class LayerConfig {
  final List<String> paths;
  final List<String> mayImport;
  final List<String> forbidImports;

  const LayerConfig({
    required this.paths,
    this.mayImport = const [],
    this.forbidImports = const [],
  });
}

class StateManagementConfig {
  final String style;
  final Map<String, Object?> rules;

  const StateManagementConfig({required this.style, this.rules = const {}});
}

class RoutingConfig {
  final String package;
  final String routerPath;

  const RoutingConfig({required this.package, required this.routerPath});
}

class ThemeConfig {
  final String path;
  final Map<String, String> brandColors;
  final Map<String, String> typography;

  /// Optional design-token catalog configuration. When null, ALEA does not
  /// load any catalog and resolvers fall back to whatever heuristic each
  /// analyzer declares (typically: no automated check). When present, the
  /// adapter named by [TokenCatalogConfig.adapter] is instantiated by
  /// `buildTokenCatalog(config)`.
  final TokenCatalogConfig? tokenCatalog;

  const ThemeConfig({
    required this.path,
    this.brandColors = const {},
    this.typography = const {},
    this.tokenCatalog,
  });
}

/// Selection + parameters for the design-token catalog adapter.
///
/// [adapter] is matched case-insensitively against the names supported by
/// `buildTokenCatalog`. [source] points at the catalog input (a directory
/// for `dart_source`, a file for `json`, a URL for HTTP-backed adapters).
/// [conventions] is a free-form bag of adapter-specific knobs — each
/// adapter declares the keys it consumes in its README.
class TokenCatalogConfig {
  final String adapter;
  final String source;
  final Map<String, Object?> conventions;

  const TokenCatalogConfig({
    required this.adapter,
    required this.source,
    this.conventions = const {},
  });
}

class TestingConfig {
  final String framework;
  final String fakesPath;
  final String pattern;
  final String overrideTarget;
  final bool preferFakesOverMocks;
  final String fakeClassPattern;

  const TestingConfig({
    required this.framework,
    required this.fakesPath,
    this.pattern = 'aaa',
    this.overrideTarget = 'repository',
    this.preferFakesOverMocks = true,
    this.fakeClassPattern = 'Fake{Name}Repository',
  });
}

class CoverageConfig {
  /// Threshold per layer name (e.g. `domain: 95`, `infrastructure: 80`).
  final Map<String, int> thresholds;

  const CoverageConfig({required this.thresholds});
}

class TicketSourceConfig {
  final String adapter;
  final Map<String, Object?> config;

  const TicketSourceConfig({required this.adapter, this.config = const {}});
}

class DesignSourceConfig {
  final String defaultAdapter;
  final Map<String, DesignAdapterConfig> adapters;

  const DesignSourceConfig({
    required this.defaultAdapter,
    this.adapters = const {},
  });
}

class DesignAdapterConfig {
  final bool enabled;
  final Map<String, Object?> options;

  const DesignAdapterConfig({required this.enabled, this.options = const {}});
}

class MrConfig {
  final String policy;
  final String branchPattern;
  final List<String> prePush;

  const MrConfig({
    required this.policy,
    required this.branchPattern,
    required this.prePush,
  });
}

class PipelineOpsConfig {
  final String defaultMode;
  final List<String> modesAvailable;
  final double costWarnUsd;
  final double costHardStopUsd;
  final UnreliableThresholdConfig unreliableThreshold;

  const PipelineOpsConfig({
    required this.defaultMode,
    required this.modesAvailable,
    required this.costWarnUsd,
    required this.costHardStopUsd,
    required this.unreliableThreshold,
  });
}

class UnreliableThresholdConfig {
  final int runsWindow;
  final int badRunsRequired;
  final int manualCorrectionsPerRun;

  const UnreliableThresholdConfig({
    required this.runsWindow,
    required this.badRunsRequired,
    required this.manualCorrectionsPerRun,
  });
}

class GatesConfig {
  /// Maps layer label → list of gate names to run for that layer.
  final Map<String, List<String>> perLayer;

  const GatesConfig({required this.perLayer});
}

class AnalyzersConfig {
  final List<String> enabled;
  final Map<String, String> severityOverrides;

  /// Per-analyzer free-form options bag. Keyed by analyzer name (`visual_fidelity`,
  /// `code_complexity`, ...) → arbitrary YAML-derived map. Each analyzer
  /// declares the keys it consumes in its README. Unknown keys are ignored;
  /// missing analyzers default to an empty map.
  ///
  /// Example consumer YAML:
  ///
  /// ```yaml
  /// analyzers:
  ///   options:
  ///     visual_fidelity:
  ///       match_threshold: 0.85
  ///       ambiguous_threshold: 0.6
  ///       check_typography: true
  /// ```
  final Map<String, Map<String, Object?>> options;

  const AnalyzersConfig({
    this.enabled = const [],
    this.severityOverrides = const {},
    this.options = const {},
  });

  /// Convenience: returns the options bag for [analyzer], never null.
  Map<String, Object?> optionsFor(String analyzer) =>
      options[analyzer] ?? const {};
}

class ProjectConfigException implements Exception {
  final String reason;
  final String? field;

  const ProjectConfigException(this.reason, {this.field});

  @override
  String toString() =>
      'ProjectConfigException(${field != null ? 'field=$field, ' : ''}reason=$reason)';
}
