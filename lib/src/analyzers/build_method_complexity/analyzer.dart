// ALEA — Build Method Complexity Analyzer.
//
// Flags build() methods that are too long or have too deeply nested
// `children:` trees.
//
// Renamed from widget_reuse_analyzer.dart in the existing pipeline — the old
// name was misleading. It does NOT measure widget reuse (that lives in
// adapters/design_source/_common/widget-audit.md). It measures build() length
// and nesting depth.
//
// Thresholds are config-exposed via `.alea.yaml`:
//   analyzers:
//     options:
//       build_method_complexity:
//         max_build_lines: 40        # default
//         max_children_depth: 4      # default
//
// The nesting checker collects ALL over-deep branches (one issue per branch
// that first exceeds the depth limit), not just the first one.

import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

import '../../contracts/analyzer.dart';

class BuildMethodComplexityAnalyzer extends Analyzer {
  @override
  String get name => 'build_method_complexity';

  @override
  Future<List<AnalysisIssue>> doAnalyze(AnalyzerContext ctx) async {
    final opts = ctx.config.analyzers.optionsFor(name);
    final maxBuildLines = (opts['max_build_lines'] as num?)?.toInt() ?? 40;
    final maxChildrenDepth = (opts['max_children_depth'] as num?)?.toInt() ?? 4;

    final issues = <AnalysisIssue>[];
    for (final filePath in ctx.filePaths) {
      late final ParseStringResult parsed;
      try {
        parsed = parseFile(
          path: filePath,
          featureSet: FeatureSet.latestLanguageVersion(),
        );
      } on FileSystemException {
        continue;
      }
      final visitor = _BuildVisitor(
        filePath,
        parsed.lineInfo,
        maxBuildLines: maxBuildLines,
        maxChildrenDepth: maxChildrenDepth,
      );
      parsed.unit.accept(visitor);
      issues.addAll(visitor.issues);
    }
    return issues;
  }
}

class _BuildVisitor extends RecursiveAstVisitor<void> {
  _BuildVisitor(
    this.filePath,
    this.lineInfo, {
    required this.maxBuildLines,
    required this.maxChildrenDepth,
  });

  final String filePath;
  final LineInfo lineInfo;
  final int maxBuildLines;
  final int maxChildrenDepth;
  final List<AnalysisIssue> issues = [];

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (node.name.lexeme == 'build') {
      _checkLength(node);
      _checkNestingDepth(node);
    }
    super.visitMethodDeclaration(node);
  }

  void _checkLength(MethodDeclaration node) {
    final startLine = lineInfo.getLocation(node.offset).lineNumber;
    final endLine = lineInfo.getLocation(node.end).lineNumber;
    final lineCount = endLine - startLine;
    if (lineCount <= maxBuildLines) return;
    issues.add(
      AnalysisIssue(
        file: filePath,
        line: startLine,
        rule: 'build_method_too_long',
        ruleId: 'build_method_complexity/too_long',
        message:
            'build() spans $lineCount lines (limit: $maxBuildLines). '
            'Extract parts into named widget classes to improve readability '
            'and enable independent rebuilds.',
        severity: Severity.major,
      ),
    );
  }

  void _checkNestingDepth(MethodDeclaration node) {
    final checker = _ChildrenDepthChecker(maxChildrenDepth);
    node.accept(checker);
    // Deduplicate identical offsets then emit one issue per violation branch.
    final offsets = checker.violationOffsets.toSet().toList();
    for (final offset in offsets) {
      final line = lineInfo.getLocation(offset).lineNumber;
      issues.add(
        AnalysisIssue(
          file: filePath,
          line: line,
          rule: 'build_nesting_too_deep',
          ruleId: 'build_method_complexity/nesting',
          message:
              'Widget tree in build() exceeds $maxChildrenDepth levels of '
              '`children:` nesting. '
              'Extract deeply nested subtrees into separate widget classes.',
          severity: Severity.major,
        ),
      );
    }
  }
}

class _ChildrenDepthChecker extends RecursiveAstVisitor<void> {
  _ChildrenDepthChecker(this.maxChildrenDepth);

  final int maxChildrenDepth;
  int _currentDepth = 0;
  int maxDepth = 0;

  /// One entry per branch that first crosses the depth limit (offset of the
  /// `children:` named expression that pushed the depth over the threshold).
  final List<int> violationOffsets = [];

  @override
  void visitNamedExpression(NamedExpression node) {
    if (node.name.label.name == 'children') {
      _currentDepth++;
      if (_currentDepth > maxDepth) {
        maxDepth = _currentDepth;
      }
      // Record a violation the first time this particular branch crosses the
      // limit (i.e. when entering it takes us from ≤max to >max).
      if (_currentDepth == maxChildrenDepth + 1) {
        violationOffsets.add(node.offset);
      }
      super.visitNamedExpression(node);
      _currentDepth--;
    } else {
      super.visitNamedExpression(node);
    }
  }
}
