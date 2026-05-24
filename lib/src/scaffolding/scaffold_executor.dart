// ALEA — ScaffoldExecutor.
//
// Applies a [ScaffoldPlan] to disk with strict idempotency:
//   - File matching path + identical content (same md5) → `skip`.
//   - File matching path with different content        → `modify`,
//     previous content captured for rollback.
//   - File absent                                       → `create`.
//
// Patches use the same rules. Each patch is evaluated against the current
// content of its target file; if the [WiringPatch.insertion] is already
// present (under any of the three modes' semantics), the outcome is
// `skip`.
//
// Rollback is byte-exact: for every previously-existing file the executor
// captured `previousContent` before writing; calling [rollback] restores
// each file to that content. Files that were newly `create`'d are deleted.

import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../contracts/run_journal.dart';
import '../contracts/scaffolding.dart';

class ScaffoldExecutor {
  final String projectRoot;
  final RunJournal? journal;

  ScaffoldExecutor({required this.projectRoot, this.journal});

  /// Validate [plan] and apply every entry to disk. Returns one outcome per
  /// (file, patch) entry in declaration order.
  Future<List<ScaffoldOutcome>> apply(ScaffoldPlan plan) async {
    _validate(plan);

    await journal?.record(
      JournalEvent(
        source: 'scaffold:executor',
        kind: JournalEventKind.started,
        payload: {
          'adapter': plan.adapterName,
          'files': plan.files.length,
          'patches': plan.patches.length,
        },
      ),
    );

    final outcomes = <ScaffoldOutcome>[];
    for (final f in plan.files) {
      outcomes.add(await _applyFile(f));
    }
    for (final patch in plan.patches) {
      outcomes.add(await _applyPatch(patch));
    }

    await journal?.record(
      JournalEvent(
        source: 'scaffold:executor',
        kind: JournalEventKind.completed,
        payload: {
          'created': outcomes
              .where((o) => o.action == ScaffoldAction.create)
              .length,
          'modified': outcomes
              .where((o) => o.action == ScaffoldAction.modify)
              .length,
          'skipped': outcomes
              .where((o) => o.action == ScaffoldAction.skip)
              .length,
        },
      ),
    );

    return List.unmodifiable(outcomes);
  }

  /// Undo every outcome from a previous [apply] call. Files that were
  /// `create`d are deleted. Files that were `modify`'d are restored to
  /// their `previousContent`. `skip` outcomes are left untouched.
  Future<List<ScaffoldOutcome>> rollback(List<ScaffoldOutcome> outcomes) async {
    final rolled = <ScaffoldOutcome>[];
    for (final o in outcomes) {
      switch (o.action) {
        case ScaffoldAction.create:
          final file = File(p.join(projectRoot, o.relativePath));
          if (await file.exists()) await file.delete();
          rolled.add(o.asRolledBack());
          break;
        case ScaffoldAction.modify:
          if (o.previousContent != null) {
            await _writeAtomic(o.relativePath, o.previousContent!);
          }
          rolled.add(o.asRolledBack());
          break;
        case ScaffoldAction.skip:
          rolled.add(o);
          break;
        case ScaffoldAction.rolledBack:
          rolled.add(o);
          break;
      }
    }
    await journal?.record(
      JournalEvent(
        source: 'scaffold:executor',
        kind: JournalEventKind.warning,
        payload: {
          'event': 'rollback',
          'files_rolled': rolled
              .where((o) => o.action == ScaffoldAction.rolledBack)
              .length,
        },
      ),
    );
    return List.unmodifiable(rolled);
  }

  // ── Internals ───────────────────────────────────────────────────────────

  void _validate(ScaffoldPlan plan) {
    final seen = <String>{};
    for (final f in plan.files) {
      _validateRelative(f.relativePath);
      if (!seen.add(f.relativePath)) {
        throw ScaffoldPlanException('duplicate file entry "${f.relativePath}"');
      }
    }
    for (final patch in plan.patches) {
      _validateRelative(patch.relativePath);
    }
  }

  void _validateRelative(String relativePath) {
    if (p.isAbsolute(relativePath)) {
      throw ScaffoldPlanException(
        'absolute paths are not allowed: "$relativePath"',
      );
    }
    if (relativePath.contains('..')) {
      throw ScaffoldPlanException(
        'parent-directory traversal not allowed: "$relativePath"',
      );
    }
  }

  Future<ScaffoldOutcome> _applyFile(GeneratedFile gen) async {
    final absPath = p.join(projectRoot, gen.relativePath);
    final file = File(absPath);
    final newMd5 = _md5(gen.content);

    if (await file.exists()) {
      final existing = await file.readAsString();
      if (_md5(existing) == newMd5) {
        await journal?.record(
          JournalEvent(
            source: 'scaffold:executor',
            kind: JournalEventKind.check,
            payload: {
              'path': gen.relativePath,
              'action': 'skip',
              'md5': newMd5,
            },
          ),
        );
        return ScaffoldOutcome(
          relativePath: gen.relativePath,
          action: ScaffoldAction.skip,
          previousContent: existing,
          newMd5: newMd5,
        );
      }
      await _writeAtomic(gen.relativePath, gen.content);
      await journal?.record(
        JournalEvent(
          source: 'scaffold:executor',
          kind: JournalEventKind.check,
          payload: {
            'path': gen.relativePath,
            'action': 'modify',
            'md5': newMd5,
          },
        ),
      );
      return ScaffoldOutcome(
        relativePath: gen.relativePath,
        action: ScaffoldAction.modify,
        previousContent: existing,
        newMd5: newMd5,
      );
    }
    await _writeAtomic(gen.relativePath, gen.content);
    await journal?.record(
      JournalEvent(
        source: 'scaffold:executor',
        kind: JournalEventKind.check,
        payload: {'path': gen.relativePath, 'action': 'create', 'md5': newMd5},
      ),
    );
    return ScaffoldOutcome(
      relativePath: gen.relativePath,
      action: ScaffoldAction.create,
      previousContent: null,
      newMd5: newMd5,
    );
  }

  Future<ScaffoldOutcome> _applyPatch(WiringPatch patch) async {
    final absPath = p.join(projectRoot, patch.relativePath);
    final file = File(absPath);
    if (!await file.exists()) {
      throw ScaffoldPlanException(
        'patch target does not exist: ${patch.relativePath}',
      );
    }
    final existing = await file.readAsString();

    if (existing.contains(patch.insertion)) {
      return ScaffoldOutcome(
        relativePath: patch.relativePath,
        action: ScaffoldAction.skip,
        previousContent: existing,
        newMd5: _md5(existing),
      );
    }

    final updated = _applyPatchToContent(existing, patch);
    if (updated == existing) {
      // Anchor not found and mode wasn't appendIfMissing — keep file intact
      // but report a skip with a journal warning so callers see the gap.
      await journal?.record(
        JournalEvent(
          source: 'scaffold:executor',
          kind: JournalEventKind.warning,
          payload: {
            'path': patch.relativePath,
            'reason': 'anchor not found, mode=${patch.mode.name}',
          },
        ),
      );
      return ScaffoldOutcome(
        relativePath: patch.relativePath,
        action: ScaffoldAction.skip,
        previousContent: existing,
        newMd5: _md5(existing),
      );
    }

    await _writeAtomic(patch.relativePath, updated);
    return ScaffoldOutcome(
      relativePath: patch.relativePath,
      action: ScaffoldAction.modify,
      previousContent: existing,
      newMd5: _md5(updated),
    );
  }

  String _applyPatchToContent(String existing, WiringPatch patch) {
    switch (patch.mode) {
      case WiringPatchMode.appendIfMissing:
        final separator = existing.endsWith('\n') ? '' : '\n';
        return '$existing$separator${patch.insertion}';
      case WiringPatchMode.insertAfterAnchor:
      case WiringPatchMode.insertBeforeAnchor:
        final anchor = patch.anchor;
        if (anchor == null) return existing;
        final lines = existing.split('\n');
        for (var i = 0; i < lines.length; i++) {
          if (lines[i].contains(anchor)) {
            final at = patch.mode == WiringPatchMode.insertAfterAnchor
                ? i + 1
                : i;
            lines.insert(at, patch.insertion);
            return lines.join('\n');
          }
        }
        return existing;
    }
  }

  Future<void> _writeAtomic(String relativePath, String content) async {
    final absPath = p.join(projectRoot, relativePath);
    final parent = Directory(p.dirname(absPath));
    if (!await parent.exists()) await parent.create(recursive: true);
    await File(absPath).writeAsString(content, flush: true);
  }

  String _md5(String s) => md5.convert(s.codeUnits).toString();
}
