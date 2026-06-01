/// alea_flow — the Flutter pipeline tool from the ALEA suite.
///
/// Public surface: the contract interfaces and types under `src/contracts/`.
/// Concrete implementations (analyzers, gates) are exported individually below
/// so consumers can pick exactly what they wire into their gate pipeline.
///
/// See `package:alea_flow/<thing>.dart` paths after this barrel — direct
/// imports of `src/...` are an internal detail and may move without a major
/// bump.
library;

// ── Contracts (stable API) ──────────────────────────────────────────────────
export 'src/contracts/analyzer.dart';
export 'src/contracts/project_config.dart';
export 'src/contracts/ticket_source_adapter.dart';
export 'src/contracts/design_source_adapter.dart';
export 'src/contracts/code_gen_adapter.dart';
export 'src/contracts/context_packet.dart';
export 'src/contracts/design_token_catalog.dart';
export 'src/contracts/run_journal.dart';
export 'src/contracts/scaffolding.dart';
export 'src/contracts/token_resolver.dart';
export 'src/contracts/widget_inventory.dart';

// ── Adapters: code generation ──────────────────────────────────────────────
//
// One executable adapter per state-management style. Selection at runtime
// happens via `state_management.style` in `.alea.yaml`; consumers can also
// pass an explicit adapter to `CodeGenOrchestrator`.
export 'src/adapters/code_gen/bloc/adapter.dart';
export 'src/adapters/code_gen/riverpod_manual/adapter.dart';

// ── Adapters: token catalog ─────────────────────────────────────────────────
//
// Concrete adapters are exposed for direct instantiation by tests and by
// consumer code that wires its own pipeline. The factory is the recommended
// entry point.
export 'src/adapters/token_catalog/factory.dart'
    show buildTokenCatalog, supportedTokenCatalogAdapters;

// ── Inventory services ──────────────────────────────────────────────────────
export 'src/inventory/in_memory_widget_inventory.dart';
export 'src/inventory/symbol_digest.dart';
export 'src/inventory/widget_inventory_builder.dart'
    show
        WidgetInventoryBuilder,
        defaultWidgetSuffixes,
        defaultWidgetBases,
        defaultTokenClasses;

// ── Scaffolding services (template engine, executor, verifier, orchestrator) ──
export 'src/scaffolding/code_gen_orchestrator.dart';
export 'src/scaffolding/scaffold_executor.dart';
export 'src/scaffolding/scaffold_verifier.dart';
export 'src/scaffolding/template_engine.dart';

// ── Resolvers (services over the DesignTokenCatalog contract) ──────────────
//
// Resolvers are NOT adapters: they do no I/O of their own and depend only on
// the catalog contract + the pure matching/ library. They live outside
// `lib/src/adapters/` so analyzers can consume them directly (the
// `analyzers_isolation` boundary rule still forbids importing adapters).
export 'src/resolvers/palette/resolver.dart';
export 'src/resolvers/type_scale/resolver.dart';
export 'src/resolvers/layout_metric/resolver.dart';
export 'src/resolvers/component_lookup/resolver.dart';

// ── Analyzers (concrete implementations) ────────────────────────────────────
export 'src/analyzers/build_method_complexity/analyzer.dart';
export 'src/analyzers/code_complexity/analyzer.dart';
export 'src/analyzers/design_principles/analyzer.dart';
export 'src/analyzers/dry_detection/analyzer.dart';
export 'src/analyzers/flutter_antipatterns/analyzer.dart';
export 'src/analyzers/layer_integrity/analyzer.dart';
export 'src/analyzers/meaningful_test/analyzer.dart';
export 'src/analyzers/package_boundary/analyzer.dart';
export 'src/analyzers/performance/analyzer.dart';
export 'src/analyzers/project_conventions/analyzer.dart';
export 'src/analyzers/security/analyzer.dart';
export 'src/analyzers/state_mgmt/analyzer.dart';
export 'src/analyzers/testing/analyzer.dart';
export 'src/analyzers/visual_fidelity/analyzer.dart';
export 'src/analyzers/widget_inventory/analyzer.dart';
export 'src/analyzers/widget_purity/analyzer.dart';
export 'src/analyzers/wiring_cohesion/analyzer.dart';

// ── Core orchestration (config loader, runner, reporter, registry) ──────────
export 'src/core/config/loader.dart';
export 'src/core/context/context_packet_builder.dart';
export 'src/core/journal/jsonl_run_journal.dart';
export 'src/core/journal/null_run_journal.dart';
export 'src/core/registry.dart';
export 'src/core/reporter.dart';
export 'src/core/runner.dart';
