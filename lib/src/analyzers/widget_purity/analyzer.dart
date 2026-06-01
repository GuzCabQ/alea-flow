// ALEA — Widget Purity Analyzer.
//
// Flags work that happens inside `build()` and shouldn't: for/while/do loops,
// .sort() calls. build() runs every frame, so anything non-trivial here is a
// per-frame perf bug.
//
// Ported from tools/pipeline/lib/src/analyzers/widget_purity_analyzer.dart.

import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

import '../../contracts/analyzer.dart';

class WidgetPurityAnalyzer extends Analyzer {
  @override
  String get name => 'widget_purity';

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
      final visitor = _PurityVisitor(filePath, parsed.lineInfo);
      parsed.unit.accept(visitor);
      issues.addAll(visitor.issues);
    }
    return issues;
  }
}

class _PurityVisitor extends RecursiveAstVisitor<void> {
  _PurityVisitor(this.filePath, this.lineInfo);
  final String filePath;
  final LineInfo lineInfo;
  final List<AnalysisIssue> issues = [];

  bool _inBuildMethod = false;
  int _closureDepthInBuild = 0;

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (node.name.lexeme == 'build') {
      _inBuildMethod = true;
      super.visitMethodDeclaration(node);
      _inBuildMethod = false;
    } else {
      super.visitMethodDeclaration(node);
    }
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {
    if (_inBuildMethod) {
      _closureDepthInBuild++;
      super.visitFunctionExpression(node);
      _closureDepthInBuild--;
    } else {
      super.visitFunctionExpression(node);
    }
  }

  bool get _directlyInBuild => _inBuildMethod && _closureDepthInBuild == 0;

  @override
  void visitForStatement(ForStatement node) {
    if (_directlyInBuild) _emitLoop(node.offset, 'for');
    super.visitForStatement(node);
  }

  @override
  void visitWhileStatement(WhileStatement node) {
    if (_directlyInBuild) _emitLoop(node.offset, 'while');
    super.visitWhileStatement(node);
  }

  @override
  void visitDoStatement(DoStatement node) {
    if (_directlyInBuild) _emitLoop(node.offset, 'do-while');
    super.visitDoStatement(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (_directlyInBuild && node.methodName.name == 'sort') {
      final line = lineInfo.getLocation(node.offset).lineNumber;
      issues.add(
        AnalysisIssue(
          file: filePath,
          line: line,
          rule: 'sort_in_build',
          ruleId: 'widget_purity/sort_in_build',
          message:
              '.sort() called directly inside build(). Sorting on every '
              'rebuild is O(n log n) per frame. Cache the sorted result in a '
              'getter or state field.',
          severity: Severity.major,
        ),
      );
    }
    super.visitMethodInvocation(node);
  }

  void _emitLoop(int offset, String loopKind) {
    final line = lineInfo.getLocation(offset).lineNumber;
    issues.add(
      AnalysisIssue(
        file: filePath,
        line: line,
        rule: 'build_heavy_loop',
        ruleId: 'widget_purity/build_heavy_loop',
        message:
            '$loopKind loop detected directly inside build(). '
            'build() is called on every frame — move iteration logic to a '
            'getter, cached field, or builder widget.',
        severity: Severity.major,
      ),
    );
  }
}
