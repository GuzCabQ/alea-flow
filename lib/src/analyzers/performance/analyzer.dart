// ALEA — Performance Analyzer.
//
// Flags two perf hazards:
//   - Expensive iterable operations (.where/.sort/.expand/.fold/.reduce/.toMap)
//     called inside build().
//   - Image.network() without cacheWidth/cacheHeight (loads full-resolution).
//
// Ported from tools/pipeline/lib/src/analyzers/performance_analyzer.dart.

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:path/path.dart' as p;

import '../../contracts/analyzer.dart';

const _expensiveMethods = {
  'where',
  'sort',
  'expand',
  'fold',
  'reduce',
  'toMap',
};

class PerformanceAnalyzer extends Analyzer {
  @override
  String get name => 'performance';

  @override
  Future<List<AnalysisIssue>> doAnalyze(AnalyzerContext ctx) async {
    final issues = <AnalysisIssue>[];
    for (final filePath in ctx.filePaths.map(p.normalize)) {
      late final ParseStringResult parsed;
      try {
        parsed = parseFile(
          path: filePath,
          featureSet: FeatureSet.latestLanguageVersion(),
          throwIfDiagnostics: false,
        );
      } on Exception {
        continue;
      }
      final visitor = _PerformanceVisitor(parsed.lineInfo);
      parsed.unit.accept(visitor);
      for (final raw in visitor.issues) {
        issues.add(raw.toIssue(filePath));
      }
    }
    return issues;
  }
}

class _PerformanceVisitor extends RecursiveAstVisitor<void> {
  _PerformanceVisitor(this.lineInfo);
  final LineInfo lineInfo;
  final List<_RawIssue> issues = [];
  bool _inBuildMethod = false;

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    final was = _inBuildMethod;
    _inBuildMethod = node.name.lexeme == 'build';
    super.visitMethodDeclaration(node);
    _inBuildMethod = was;
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (_inBuildMethod) _checkExpensiveInBuild(node);
    _checkImageNetworkNoCache(node);
    super.visitMethodInvocation(node);
  }

  void _checkExpensiveInBuild(MethodInvocation node) {
    final method = node.methodName.name;
    if (!_expensiveMethods.contains(method)) return;
    final line = lineInfo.getLocation(node.offset).lineNumber;
    issues.add(
      _RawIssue(
        line: line,
        rule: 'expensive_operation_in_build',
        ruleId: 'performance/expensive_in_build',
        message:
            'Calling .$method() inside build() rebuilds on every frame. '
            'Pre-compute in the provider or cache outside build().',
        severity: Severity.major,
      ),
    );
  }

  void _checkImageNetworkNoCache(MethodInvocation node) {
    if (node.methodName.name != 'network') return;
    final target = node.target;
    if (target is! SimpleIdentifier || target.name != 'Image') return;
    final hasCache = node.argumentList.arguments.any((a) {
      if (a is! NamedExpression) return false;
      final name = a.name.label.name;
      return name == 'cacheWidth' || name == 'cacheHeight';
    });
    if (hasCache) return;
    final line = lineInfo.getLocation(node.offset).lineNumber;
    issues.add(
      _RawIssue(
        line: line,
        rule: 'image_network_no_cache',
        ruleId: 'performance/image_no_cache',
        message:
            'Image.network() without cacheWidth/cacheHeight loads full '
            'resolution images. Add cacheWidth or cacheHeight to reduce memory.',
        severity: Severity.minor,
      ),
    );
  }
}

class _RawIssue {
  const _RawIssue({
    required this.line,
    required this.rule,
    required this.ruleId,
    required this.message,
    required this.severity,
  });
  final int line;
  final String rule;
  final String ruleId;
  final String message;
  final Severity severity;

  AnalysisIssue toIssue(String file) => AnalysisIssue(
    file: file,
    line: line,
    rule: rule,
    ruleId: ruleId,
    message: message,
    severity: severity,
  );
}
