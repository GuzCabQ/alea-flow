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
  // End offset of the first `await` expression. The function only suspends
  // AFTER the awaited expression is fully evaluated, so `context` used WITHIN
  // it (e.g. as an argument: `await showDialog(context: context)`) is read
  // before the gap and is safe. Only `context` past this point is "after await".
  int _firstAwaitEnd = -1;
  int _contextAfterAwaitOffset = -1;
  int _mountedOffset = -1; // offset of the first `mounted` reference, or -1

  @override
  void visitFunctionExpression(FunctionExpression node) {
    // Nested closures are separate async scopes — do not descend.
  }

  @override
  void visitAwaitExpression(AwaitExpression node) {
    if (_firstAwaitEnd == -1) _firstAwaitEnd = node.end;
    super.visitAwaitExpression(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    switch (node.name) {
      case 'mounted':
        if (_mountedOffset == -1) _mountedOffset = node.offset;
      case 'context':
        // `context.mounted` is a mounted-guard expression, not a context use.
        // Detect it by checking whether this `context` is the prefix of a
        // PrefixedIdentifier whose identifier is `mounted`.
        final parent = node.parent;
        if (parent is PrefixedIdentifier &&
            parent.identifier.name == 'mounted') {
          // Record this as a mounted check at the `context` offset.
          if (_mountedOffset == -1) _mountedOffset = node.offset;
          break;
        }
        if (_firstAwaitEnd != -1 &&
            node.offset >= _firstAwaitEnd &&
            _contextAfterAwaitOffset == -1) {
          _contextAfterAwaitOffset = node.offset;
        }
    }
  }

  bool get hasViolation =>
      _firstAwaitEnd != -1 &&
      _contextAfterAwaitOffset != -1 &&
      // guarded only if a mounted check appears at-or-before the post-await use
      !(_mountedOffset != -1 && _mountedOffset <= _contextAfterAwaitOffset);
  int get violationOffset => _contextAfterAwaitOffset;
}
