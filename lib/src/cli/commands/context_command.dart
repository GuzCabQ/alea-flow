// ALEA — `aflow context` subcommand.
//
// Builds (or reuses) the context-packet.md for a given run directory.
// Optimised for being called by skills before they hit the LLM —
// guarantees a hash-stable prefix within the configured TTL.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../../contracts/context_packet.dart';
import '../../core/context/context_packet_builder.dart';

class ContextCommand extends Command<int> {
  ContextCommand() {
    argParser
      ..addOption(
        'project-root',
        abbr: 'r',
        defaultsTo: '.',
        help: 'Root directory of the consumer Flutter project.',
      )
      ..addOption(
        'run-directory',
        abbr: 'd',
        help:
            'Path to the pipeline run directory where the packet is '
            'persisted as `context-packet.md`. When omitted, the packet '
            'is built in memory and printed to stdout.',
      )
      ..addFlag(
        'force',
        negatable: false,
        help: 'Regenerate even when a fresh packet exists.',
      )
      ..addOption(
        'ttl-minutes',
        defaultsTo: '5',
        help: 'Time-to-live for the packet, in minutes.',
      )
      ..addOption(
        'format',
        abbr: 'f',
        allowed: ['body', 'full'],
        defaultsTo: 'body',
        help:
            '`body` prints the markdown only; '
            '`full` prints front-matter + body (round-trippeable).',
      );
  }

  @override
  String get name => 'context';

  @override
  String get description => 'Build (or reuse) the context-packet.md.';

  @override
  Future<int> run() async {
    final res = argResults!;
    final projectRoot = p.canonicalize(res['project-root'] as String);
    final runDirArg = res['run-directory'] as String?;
    final runDir = runDirArg != null ? p.canonicalize(runDirArg) : null;
    final force = res['force'] as bool;
    final format = res['format'] as String;
    final ttlMinutes = int.tryParse(res['ttl-minutes'] as String) ?? 5;

    final builder = ContextPacketBuilder(
      projectRoot: projectRoot,
      ttl: Duration(minutes: ttlMinutes),
    );

    final ContextPacket packet;
    try {
      packet = await builder.build(runDirectory: runDir, force: force);
    } on ContextPacketException catch (e) {
      stderr.writeln('Error: ${e.message}');
      return 2;
    }

    stdout.writeln(format == 'full' ? packet.render() : packet.body);
    if (runDir != null) {
      stderr.writeln(
        'Packet hash: ${packet.hash} '
        '(expires ${packet.expiresAt.toIso8601String()})',
      );
    }
    return 0;
  }
}
