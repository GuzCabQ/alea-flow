import 'dart:convert';
import 'package:alea_flow/src/cli/report/html_report.dart';
import 'package:alea_flow/src/contracts/analyzer.dart';
import 'package:test/test.dart';

GateReport _report() => GateReport(
  gate: 'full',
  timestamp: DateTime.utc(2026, 5, 29, 13, 42),
  results: [
    AnalysisResult(
      analyzer: 'security',
      issues: [
        AnalysisIssue(
          file: 'lib/src/domain/x.dart',
          line: 1,
          rule: 'dart_io_in_domain',
          ruleId: 'security/dart_io_in_domain',
          message: 'no dart:io',
          suggestedFix: 'move it',
          severity: Severity.blocker,
        ),
      ],
    ),
    AnalysisResult(
      analyzer: 'visual_fidelity',
      issues: [
        AnalysisIssue(
          file: 'lib/src/presentation/c.dart',
          line: 38,
          rule: 'missing_image_fit',
          ruleId: 'visual_fidelity/missing_image_fit',
          message: 'no fit',
          severity: Severity.minor,
        ), // no suggestedFix → must be omitted
      ],
    ),
  ],
);

void main() {
  group('renderHtmlReport', () {
    final files = renderHtmlReport(_report(), project: 'freya');

    test('emits exactly the four files', () {
      expect(files.keys.toSet(), {
        'index.html',
        'styles.css',
        'app.js',
        'report.json',
      });
    });

    test('index.html injects data and consumes the marker', () {
      final html = files['index.html']!;
      expect(html, contains('window.__ALEA_REPORT__ ='));
      expect(html, isNot(contains('__ALEA_DATA__')));
    });

    test('payload round-trips with project and the real snake_case schema', () {
      final data = jsonDecode(files['report.json']!) as Map<String, Object?>;
      expect(data['gate'], 'full');
      expect(data['passed'], false);
      expect(data['project'], 'freya');
      expect((data['summary'] as Map)['blockers'], 1);
      final sec =
          (data['results'] as List).firstWhere(
                (r) => r['analyzer'] == 'security',
              )
              as Map;
      final issue = (sec['issues'] as List).first as Map;
      expect(issue['rule_id'], 'security/dart_io_in_domain');
      expect(issue['suggested_fix'], 'move it');
      final vf =
          (data['results'] as List).firstWhere(
                (r) => r['analyzer'] == 'visual_fidelity',
              )
              as Map;
      final minorIssue = (vf['issues'] as List).first as Map;
      expect(
        minorIssue.containsKey('suggested_fix'),
        isFalse,
      ); // omitted when null
    });

    test('css and js are emitted non-empty', () {
      expect(files['styles.css']!.trim(), isNotEmpty);
      expect(files['app.js']!.trim(), isNotEmpty);
    });
  });
}
