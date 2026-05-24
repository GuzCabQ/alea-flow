// ALEA — State Management Validator.
//
// Detects Riverpod (manual) antipatterns:
//   - ref.watch() inside a Notifier method (creates stale subscriptions).
//   - Provider() declared inside build() (recreates on every rebuild).
//
// Config-aware: only runs when `config.state_management.style == "riverpod_manual"`.
// Other style adapters (bloc, provider) get their own analyzer presets later.
//
// Ported from tools/pipeline/lib/src/analyzers/state_mgmt_validator.dart.

import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

import '../../contracts/analyzer.dart';

class StateMgmtAnalyzer extends Analyzer {
  @override
  String get name => 'state_mgmt';

  @override
  Future<List<AnalysisIssue>> doAnalyze(AnalyzerContext ctx) async {
    // Currently only the riverpod_manual preset has rules. Other styles
    // (bloc, provider, getx) emit nothing here until their own presets ship.
    if (ctx.config.stateManagement.style != 'riverpod_manual') return const [];

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
      final visitor = _StateMgmtVisitor(filePath, parsed.lineInfo);
      parsed.unit.accept(visitor);
      issues.addAll(visitor.issues);
    }
    return issues;
  }
}

class _StateMgmtVisitor extends RecursiveAstVisitor<void> {
  _StateMgmtVisitor(this.filePath, this.lineInfo);
  final String filePath;
  final LineInfo lineInfo;
  final List<AnalysisIssue> issues = [];

  bool _inNotifierClass = false;
  bool _inBuildMethod = false;
  int _closureDepthInBuild = 0;

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final prev = _inNotifierClass;
    _inNotifierClass = node.namePart.typeName.lexeme.endsWith('Notifier');
    super.visitClassDeclaration(node);
    _inNotifierClass = prev;
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    final prev = _inBuildMethod;
    _inBuildMethod = node.name.lexeme == 'build';
    super.visitMethodDeclaration(node);
    _inBuildMethod = prev;
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
    _checkRefWatchInNotifier(node);
    _checkProviderInBuild(node);
    super.visitMethodInvocation(node);
  }

  void _checkRefWatchInNotifier(MethodInvocation node) {
    if (!_inNotifierClass || _inBuildMethod) return;
    final target = node.target;
    if (target is! SimpleIdentifier || target.name != 'ref') return;
    if (node.methodName.name != 'watch') return;
    final line = lineInfo.getLocation(node.offset).lineNumber;
    issues.add(
      AnalysisIssue(
        file: filePath,
        line: line,
        rule: 'ref_watch_in_notifier',
        ruleId: 'state_mgmt/ref_watch_in_notifier_method',
        message:
            'ref.watch() inside a Notifier method creates a stale subscription. '
            'Use ref.read() to read a value once, or ref.listen() for side effects.',
        severity: Severity.major,
      ),
    );
  }

  void _checkProviderInBuild(MethodInvocation node) {
    if (!_inBuildMethod || _closureDepthInBuild > 0) return;
    if (node.target != null) return;
    if (!node.methodName.name.endsWith('Provider')) return;
    final line = lineInfo.getLocation(node.offset).lineNumber;
    issues.add(
      AnalysisIssue(
        file: filePath,
        line: line,
        rule: 'provider_in_build',
        ruleId: 'state_mgmt/provider_in_build',
        message:
            'Provider created directly inside build(). Providers are '
            'recreated on every rebuild, losing all cached state. Move the '
            'provider definition to the top level.',
        severity: Severity.major,
      ),
    );
  }
}
