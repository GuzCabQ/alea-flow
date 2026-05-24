// ALEA — Gate report formatting.
//
// Two output formats: human-readable (terminal) and JSON (for machine
// consumption by `/run-gates` and `/pipeline-feedback`).

import 'dart:convert';

import '../contracts/analyzer.dart';

class GateReporter {
  String toJsonString(GateReport report) =>
      const JsonEncoder.withIndent('  ').convert(report.toJson());

  String toHumanReadable(GateReport report) {
    final buffer = StringBuffer();
    final status = report.passed ? 'PASSED ✓' : 'FAILED ✗';

    buffer.writeln('═══════════════════════════════════════');
    buffer.writeln('Gate: ${report.gate}  —  $status');
    buffer.writeln('═══════════════════════════════════════');

    for (final result in report.results) {
      final mark = result.passed ? '✓' : '✗';
      buffer.writeln('  $mark ${result.analyzer}');

      for (final issue in result.issues) {
        final loc = issue.line != null ? ':${issue.line}' : '';
        buffer.writeln(
          '    [${issue.severity.name.toUpperCase()}] ${issue.file}$loc',
        );
        buffer.writeln('    → ${issue.message}');
        if (issue.suggestedFix != null) {
          buffer.writeln('    fix: ${issue.suggestedFix}');
        }
      }
    }

    if (report.metrics.isNotEmpty) {
      buffer.writeln('───────────────────────────────────────');
      buffer.writeln('Metrics:');
      report.metrics.forEach((k, v) => buffer.writeln('  $k: $v'));
    }

    buffer.writeln('───────────────────────────────────────');
    final summary = report.toJson()['summary'] as Map<String, Object?>;
    buffer.writeln(
      'Total: ${summary['total_issues']} issues  '
      '(${summary['blockers']} blockers, '
      '${summary['criticals']} criticals, '
      '${summary['majors']} majors, '
      '${summary['minors']} minors)',
    );

    return buffer.toString();
  }
}
