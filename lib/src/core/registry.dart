// ALEA — Analyzer registry.
//
// The canonical list of analyzers ALEA knows about. Add a new analyzer here
// after porting. Order is not significant; analyzers run concurrently.

import '../analyzers/build_method_complexity/analyzer.dart';
import '../analyzers/code_complexity/analyzer.dart';
import '../analyzers/design_principles/analyzer.dart';
import '../analyzers/dry_detection/analyzer.dart';
import '../analyzers/flutter_antipatterns/analyzer.dart';
import '../analyzers/layer_integrity/analyzer.dart';
import '../analyzers/meaningful_test/analyzer.dart';
import '../analyzers/package_boundary/analyzer.dart';
import '../analyzers/performance/analyzer.dart';
import '../analyzers/project_conventions/analyzer.dart';
import '../analyzers/security/analyzer.dart';
import '../analyzers/state_mgmt/analyzer.dart';
import '../analyzers/testing/analyzer.dart';
import '../analyzers/visual_fidelity/analyzer.dart';
import '../analyzers/widget_inventory/analyzer.dart';
import '../analyzers/widget_purity/analyzer.dart';
import '../analyzers/wiring_cohesion/analyzer.dart';
import '../contracts/analyzer.dart';

/// All registered analyzer instances.
///
/// Returns fresh instances every call so consumers can mutate or compose
/// without leaking shared state.
List<Analyzer> registeredAnalyzers() => [
  BuildMethodComplexityAnalyzer(),
  CodeComplexityAnalyzer(),
  DesignPrinciplesAnalyzer(),
  DryDetectionAnalyzer(),
  FlutterAntipatternsAnalyzer(),
  LayerIntegrityAnalyzer(),
  MeaningfulTestAnalyzer(),
  PackageBoundaryAnalyzer(),
  PerformanceAnalyzer(),
  ProjectConventionsAnalyzer(),
  SecurityAnalyzer(),
  StateMgmtAnalyzer(),
  TestingAnalyzer(),
  VisualFidelityAnalyzer(),
  WidgetInventoryAnalyzer(),
  WidgetPurityAnalyzer(),
  WiringCohesionAnalyzer(),
];
