// ALEA — Flutter Antipatterns Analyzer.
//
// Catches:
//   - setState() called directly inside build() → infinite rebuild.
//   - BuildContext used after `await` without a `mounted` check.
//
// Ported from tools/pipeline/lib/src/analyzers/flutter_antipatterns_analyzer.dart.

import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

import '../../contracts/analyzer.dart';

class FlutterAntipatternsAnalyzer extends Analyzer {
  @override
  String get name => 'flutter_antipatterns';

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
      final visitor = _PatternsVisitor(filePath, parsed.lineInfo);
      parsed.unit.accept(visitor);
      issues.addAll(visitor.issues);
    }
    return issues;
  }
}

class _PatternsVisitor extends RecursiveAstVisitor<void> {
  _PatternsVisitor(this.filePath, this.lineInfo);
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
      _checkAsyncContextUsage(node.body);
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

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (_inBuildMethod &&
        _closureDepthInBuild == 0 &&
        node.target == null &&
        node.methodName.name == 'setState') {
      final line = lineInfo.getLocation(node.offset).lineNumber;
      issues.add(
        AnalysisIssue(
          file: filePath,
          line: line,
          rule: 'setState_in_build',
          ruleId: 'flutter_antipatterns/set_state_in_build',
          message:
              'setState() called directly inside build(). '
              'This causes an infinite rebuild loop. '
              'Move state mutations to event handlers.',
          severity: Severity.critical,
        ),
      );
    }
    super.visitMethodInvocation(node);
  }

  void _checkAsyncContextUsage(FunctionBody body) {
    if (body is! BlockFunctionBody) return;
    if (body.keyword?.lexeme != 'async') return;
    final checker = _AsyncContextChecker();
    body.accept(checker);
    if (checker.hasViolation) {
      final line = lineInfo.getLocation(checker.violationOffset).lineNumber;
      issues.add(
        AnalysisIssue(
          file: filePath,
          line: line,
          rule: 'context_after_async_gap',
          ruleId: 'flutter_antipatterns/context_after_async',
          message:
              'BuildContext used after `await` without checking `mounted`. '
              'The widget may have been disposed by the time the async gap '
              'completes. Add `if (!mounted) return;` before using context.',
          severity: Severity.critical,
        ),
      );
    }
  }
}

class _AsyncContextChecker extends RecursiveAstVisitor<void> {
  int _firstAwaitOffset = -1;
  int _contextAfterAwaitOffset = -1;
  bool _hasMountedCheck = false;

  @override
  void visitFunctionExpression(FunctionExpression node) {
    // Nested closures are separate async scopes — do not descend.
  }

  @override
  void visitAwaitExpression(AwaitExpression node) {
    if (_firstAwaitOffset == -1) _firstAwaitOffset = node.offset;
    super.visitAwaitExpression(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    switch (node.name) {
      case 'mounted':
        _hasMountedCheck = true;
      case 'context':
        if (_firstAwaitOffset != -1 &&
            node.offset > _firstAwaitOffset &&
            _contextAfterAwaitOffset == -1) {
          _contextAfterAwaitOffset = node.offset;
        }
    }
  }

  bool get hasViolation =>
      _firstAwaitOffset != -1 &&
      _contextAfterAwaitOffset != -1 &&
      !_hasMountedCheck;
  int get violationOffset => _contextAfterAwaitOffset;
}
