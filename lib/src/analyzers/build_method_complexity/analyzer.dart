// ALEA — Build Method Complexity Analyzer.
//
// Flags build() methods that are too long or have too deeply nested
// `children:` trees.
//
// Renamed from widget_reuse_analyzer.dart in the existing pipeline — the old
// name was misleading. It does NOT measure widget reuse (that lives in
// adapters/design_source/_common/widget-audit.md). It measures build() length
// and nesting depth.

import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

import '../../contracts/analyzer.dart';

const _maxBuildLines = 40;
const _maxChildrenDepth = 4;

class BuildMethodComplexityAnalyzer extends Analyzer {
  @override
  String get name => 'build_method_complexity';

  @override
  Future<List<AnalysisIssue>> doAnalyze(AnalyzerContext ctx) async {
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
      final visitor = _BuildVisitor(filePath, parsed.lineInfo);
      parsed.unit.accept(visitor);
      issues.addAll(visitor.issues);
    }
    return issues;
  }
}

class _BuildVisitor extends RecursiveAstVisitor<void> {
  _BuildVisitor(this.filePath, this.lineInfo);
  final String filePath;
  final LineInfo lineInfo;
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
    if (lineCount <= _maxBuildLines) return;
    issues.add(
      AnalysisIssue(
        file: filePath,
        line: startLine,
        rule: 'build_method_too_long',
        ruleId: 'build_method_complexity/too_long',
        message:
            'build() spans $lineCount lines (limit: $_maxBuildLines). '
            'Extract parts into named widget classes to improve readability '
            'and enable independent rebuilds.',
        severity: Severity.major,
      ),
    );
  }

  void _checkNestingDepth(MethodDeclaration node) {
    final checker = _ChildrenDepthChecker();
    node.accept(checker);
    if (checker.maxDepth <= _maxChildrenDepth) return;
    final line = lineInfo.getLocation(checker.firstViolationOffset).lineNumber;
    issues.add(
      AnalysisIssue(
        file: filePath,
        line: line,
        rule: 'build_nesting_too_deep',
        ruleId: 'build_method_complexity/nesting',
        message:
            'Widget tree in build() has ${checker.maxDepth} levels of '
            '`children:` nesting (limit: $_maxChildrenDepth). '
            'Extract deeply nested subtrees into separate widget classes.',
        severity: Severity.major,
      ),
    );
  }
}

class _ChildrenDepthChecker extends RecursiveAstVisitor<void> {
  int _currentDepth = 0;
  int maxDepth = 0;
  int firstViolationOffset = -1;

  @override
  void visitNamedExpression(NamedExpression node) {
    if (node.name.label.name == 'children') {
      _currentDepth++;
      if (_currentDepth > maxDepth) {
        maxDepth = _currentDepth;
        if (maxDepth > _maxChildrenDepth && firstViolationOffset == -1) {
          firstViolationOffset = node.offset;
        }
      }
      super.visitNamedExpression(node);
      _currentDepth--;
    } else {
      super.visitNamedExpression(node);
    }
  }
}
