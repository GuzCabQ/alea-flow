import 'dart:io';
import 'package:alea_flow/src/cli/report/html_report_assets.dart';
import 'package:test/test.dart';

// Runs from the package root (the `dart test` convention). Guards that the
// embedded constants stay in sync with the source assets — if one drifts,
// re-run `dart run tool/embed_report_assets.dart`.
void main() {
  const dir = 'lib/src/cli/report/assets';
  group('embedded assets match their source files', () {
    test('styles.css', () {
      expect(stylesCss, File('$dir/styles.css').readAsStringSync());
    });
    test('app.js', () {
      expect(appJs, File('$dir/app.js').readAsStringSync());
    });
    test('index.html.tmpl', () {
      expect(
        indexHtmlTemplate,
        File('$dir/index.html.tmpl').readAsStringSync(),
      );
    });
  });
}
