// test/cli/graph_smoke_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:alea_flow/src/cli/cli_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('aflow graph builds graph.json and graph-query reads it', () async {
    final tmp = Directory.systemTemp.createTempSync('aflow_graph_smoke_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final out = p.join(tmp.path, 'graph.json');

    // Build over alea-flow's own repo (cwd during `dart test` = package root).
    final buildCode = await AleaCliRunner().run([
      'graph',
      '-r',
      '.',
      '-o',
      out,
    ]);
    expect(buildCode, 0);

    final doc =
        jsonDecode(File(out).readAsStringSync()) as Map<String, Object?>;
    expect((doc['nodes'] as List), isNotEmpty);
    expect((doc['edges'] as List), isNotEmpty);

    // Query the built graph.
    final qCode = await AleaCliRunner().run([
      'graph-query',
      'god-nodes',
      '-i',
      out,
    ]);
    expect(qCode, 0);
  });
}
