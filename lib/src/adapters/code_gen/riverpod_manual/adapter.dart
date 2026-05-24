// ALEA — RiverpodManualCodeGen.
//
// Emits a minimal Riverpod (manual style — no codegen) feature scaffold:
//
//   <feature>_state.dart      — immutable State + copyWith
//   <feature>_notifier.dart   — Notifier<State> + NotifierProvider
//   <feature>_screen.dart     — ConsumerWidget reading the provider
//
// The adapter is config-driven: paths come from
// `architecture.layers.<layer>.paths`. No path is hardcoded.

import 'dart:async';

import '../../../contracts/code_gen_adapter.dart';
import '../../../contracts/project_config.dart';
import '../../../contracts/scaffolding.dart';
import '../../../scaffolding/template_engine.dart';
import 'templates.dart';

class RiverpodManualCodeGen implements CodeGenAdapter {
  final TemplateEngine _engine = TemplateEngine();

  @override
  String get name => 'riverpod_manual';

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

    final files = <GeneratedFile>[];

    final stateClass = '${_pascal(feature)}State';
    final notifierClass = '${_pascal(feature)}Notifier';
    final screenClass = '${_pascal(feature)}Screen';
    final providerName = '${_camel(feature)}NotifierProvider';

    final stateRel = '${domainPath}feature/$feature/${feature}_state.dart';
    final notifierRel =
        '${domainPath}feature/$feature/${feature}_notifier.dart';
    final screenRel =
        '${presentationPath}feature/$feature/${feature}_screen.dart';

    if (request.layer == CodeGenLayer.domain ||
        request.layer == CodeGenLayer.presentation) {
      files.add(
        GeneratedFile(
          relativePath: stateRel,
          content: _engine.render(riverpodStateTemplate, {
            'feature_human_name': humanName,
            'state_class': stateClass,
          }),
        ),
      );
      files.add(
        GeneratedFile(
          relativePath: notifierRel,
          content: _engine.render(riverpodNotifierTemplate, {
            'state_class': stateClass,
            'notifier_class': notifierClass,
            'provider_name': providerName,
            'state_import': '${feature}_state.dart',
          }),
        ),
      );
    }
    if (request.layer == CodeGenLayer.presentation) {
      files.add(
        GeneratedFile(
          relativePath: screenRel,
          content: _engine.render(riverpodScreenTemplate, {
            'feature_human_name': humanName,
            'screen_class': screenClass,
            'notifier_class': notifierClass,
            'provider_name': providerName,
            'state_class': stateClass,
            // Cross-layer relative import path. Domain lives under
            // `<domainPath>feature/<feature>/`, presentation lives under
            // `<presentationPath>feature/<feature>/`. Both paths come from
            // config — never hardcoded.
            'notifier_import': _relativeImport(
              from: screenRel,
              to: notifierRel,
            ),
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

  // ── Helpers ─────────────────────────────────────────────────────────────

  String _featureSlug(CodeGenRequest req) {
    final spec = req.spec;
    final featureBlock = spec['feature'];
    if (featureBlock is Map<String, Object?>) {
      final name = featureBlock['name'];
      if (name is String && name.isNotEmpty) return _snake(name);
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

  String _camel(String snake) {
    final pascal = _pascal(snake);
    if (pascal.isEmpty) return pascal;
    return pascal[0].toLowerCase() + pascal.substring(1);
  }

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

  /// Build a relative import path from one file to another, both
  /// project-relative. Returns a Dart-import path (forward slashes).
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
