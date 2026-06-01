// ALEA — pure HTML gate reporter. Turns a GateReport into the alea-reports/
// file set. No dart:io; the caller writes the files.
import 'dart:convert';

import '../../contracts/analyzer.dart';
import 'html_report_assets.dart';

/// Renders the report bundle. [project] is injected into the payload only —
/// the GateReport contract is not modified.
Map<String, String> renderHtmlReport(
  GateReport report, {
  required String project,
}) {
  final payload = <String, Object?>{...report.toJson(), 'project': project};
  final inline = jsonEncode(payload);
  return {
    'index.html': indexHtmlTemplate.replaceFirst('__ALEA_DATA__', inline),
    'styles.css': stylesCss,
    'app.js': appJs,
    'report.json': const JsonEncoder.withIndent('  ').convert(payload),
  };
}
