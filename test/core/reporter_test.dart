import 'package:alea_flow/src/contracts/analyzer.dart';
import 'package:alea_flow/src/core/reporter.dart';
import 'package:test/test.dart';

void main() {
  group('GateReporter.toHumanReadable', () {
    final report = GateReport(
      gate: 'full',
      timestamp: DateTime.utc(2026, 5, 29),
      results: [
        AnalysisResult(
          analyzer: 'security',
          issues: [
            AnalysisIssue(
              file: 'a.dart',
              line: 1,
              rule: 'r',
              ruleId: 'security/r',
              message: 'm',
              severity: Severity.blocker,
            ),
          ],
        ),
      ],
    );

    test('shows gate status and summary', () {
      final out = GateReporter().toHumanReadable(report);
      expect(out, contains('Gate: full'));
      expect(out, contains('FAILED'));
      expect(out, contains('Total: 1 issues'));
    });

    test('nudges the html report for discoverability', () {
      final out = GateReporter().toHumanReadable(report);
      expect(out, contains('--format html'));
      expect(out, contains('alea-reports/index.html'));
    });
  });
}
