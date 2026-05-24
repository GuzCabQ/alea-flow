// ALEA — BlocCodeGen.
//
// Emits a minimal Bloc feature scaffold:
//
//   <feature>_state.dart   — sealed state + 4 variants (Initial/Loading/Ready/Failed)
//   <feature>_event.dart   — sealed event + Start/Reset variants
//   <feature>_bloc.dart    — Bloc<Event, State> with two transitions
//   <feature>_screen.dart  — StatelessWidget hosting a BlocProvider + Builder
//
// Same orchestration model as `RiverpodManualCodeGen`: build a plan, let
// the executor + verifier handle the rest.

import 'dart:async';

import '../../../contracts/code_gen_adapter.dart';
import '../../../contracts/project_config.dart';
import '../../../contracts/scaffolding.dart';
import '../../../scaffolding/template_engine.dart';
import 'templates.dart';

class BlocCodeGen implements CodeGenAdapter {
  final TemplateEngine _engine = TemplateEngine();

  @override
  String get name => 'bloc';

  @override
  bool supports(CodeGenLayer layer, ProjectConfig config) {
    return layer == CodeGenLayer.domain || layer == CodeGenLayer.presentation;
  }

  @override
  Future<ScaffoldPlan> generate(CodeGenRequest request) async {
    final feature = _featureSlug(request);
    final humanName = _humanName(feature);

    final domainPath = _firstLayerPath(request.config, 'domain');
    final presentationPath = _firstLayerPath(request.config, 'presentation');

    final stateClass = '${_pascal(feature)}State';
    final eventClass = '${_pascal(feature)}Event';
    final blocClass = '${_pascal(feature)}Bloc';
    final screenClass = '${_pascal(feature)}Screen';

    final stateRel = '${domainPath}feature/$feature/${feature}_state.dart';
    final eventRel = '${domainPath}feature/$feature/${feature}_event.dart';
    final blocRel = '${domainPath}feature/$feature/${feature}_bloc.dart';
    final screenRel =
        '${presentationPath}feature/$feature/${feature}_screen.dart';

    final files = <GeneratedFile>[];

    if (request.layer == CodeGenLayer.domain ||
        request.layer == CodeGenLayer.presentation) {
      files.add(
        GeneratedFile(
          relativePath: stateRel,
          content: _engine.render(blocStateTemplate, {
            'state_class': stateClass,
          }),
        ),
      );
      files.add(
        GeneratedFile(
          relativePath: eventRel,
          content: _engine.render(blocEventTemplate, {
            'event_class': eventClass,
          }),
        ),
      );
      files.add(
        GeneratedFile(
          relativePath: blocRel,
          content: _engine.render(blocBlocTemplate, {
            'state_class': stateClass,
            'event_class': eventClass,
            'bloc_class': blocClass,
            'feature_human_name': humanName,
            'state_import': '${feature}_state.dart',
            'event_import': '${feature}_event.dart',
          }),
        ),
      );
    }
    if (request.layer == CodeGenLayer.presentation) {
      files.add(
        GeneratedFile(
          relativePath: screenRel,
          content: _engine.render(blocScreenTemplate, {
            'screen_class': screenClass,
            'bloc_class': blocClass,
            'state_class': stateClass,
            'feature_human_name': humanName,
            'bloc_import': _relativeImport(from: screenRel, to: blocRel),
            'state_import': _relativeImport(from: screenRel, to: stateRel),
          }),
        ),
      );
    }

    return ScaffoldPlan(
      adapterName: name,
      files: files,
      meta: {
        'feature': feature,
        'layer': request.layer.name,
        'human_name': humanName,
      },
    );
  }

  // ── Helpers (identical to RiverpodManualCodeGen — duplicated rather than
  // factoring into a shared base, to keep each adapter self-contained and
  // editable in isolation) ──────────────────────────────────────────────

  String _featureSlug(CodeGenRequest req) {
    final spec = req.spec;
    final featureBlock = spec['feature'];
    if (featureBlock is Map<String, Object?>) {
      final n = featureBlock['name'];
      if (n is String && n.isNotEmpty) return _snake(n);
    }
    final flat = spec['feature_name'];
    if (flat is String && flat.isNotEmpty) return _snake(flat);
    throw CodeGenException(
      name,
      req.layer,
      'spec must declare feature.name or feature_name',
    );
  }

  String _humanName(String slug) => slug
      .replaceAll('_', ' ')
      .split(' ')
      .map((w) {
        if (w.isEmpty) return w;
        return w[0].toUpperCase() + w.substring(1);
      })
      .join(' ');

  String _firstLayerPath(ProjectConfig config, String layerName) {
    final layer = config.architecture.layers[layerName];
    if (layer == null || layer.paths.isEmpty) {
      throw CodeGenException(
        name,
        CodeGenLayer.values.firstWhere((l) => l.name == layerName),
        'architecture.layers.$layerName.paths is empty',
      );
    }
    var path = layer.paths.first;
    if (!path.endsWith('/')) path = '$path/';
    return path;
  }

  String _pascal(String snake) => snake
      .split('_')
      .where((s) => s.isNotEmpty)
      .map((s) => s[0].toUpperCase() + s.substring(1))
      .join();

  String _snake(String input) {
    final buf = StringBuffer();
    for (var i = 0; i < input.length; i++) {
      final c = input.codeUnitAt(i);
      final isUpper = c >= 0x41 && c <= 0x5A;
      if (isUpper && i > 0) buf.write('_');
      buf.writeCharCode(isUpper ? c + 32 : c);
    }
    return buf.toString().replaceAll(RegExp(r'[^a-z0-9_]'), '_');
  }

  String _relativeImport({required String from, required String to}) {
    final fromParts = from.split('/')..removeLast();
    final toParts = to.split('/');
    var commonLen = 0;
    while (commonLen < fromParts.length &&
        commonLen < toParts.length - 1 &&
        fromParts[commonLen] == toParts[commonLen]) {
      commonLen++;
    }
    final upHops = fromParts.length - commonLen;
    final tail = toParts.sublist(commonLen).join('/');
    return List.filled(upHops, '..').followedBy([tail]).join('/');
  }
}
