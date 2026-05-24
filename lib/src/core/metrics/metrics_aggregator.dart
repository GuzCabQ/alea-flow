// ALEA — Pipeline metrics aggregator.
//
// Deterministic arithmetic over `.pipeline/metrics/history.jsonl` that drives
// the pipeline's self-correction circuit breakers:
//   - the "unreliable flag" (recent runs that needed many manual corrections
//     → force `guided` mode next run)
//   - per design-source adapter hallucination rate (→ disable a noisy adapter)
//
// This was previously specified in prose for the AI to compute by hand inside
// `/pipeline-feedback`. Moving it to tested code makes the circuit-breaker
// signal trustworthy instead of AI-claimed. Replaces the never-written
// `scripts/pipeline-metrics.sh` (Dart-first; no fragile shell JSON parsing).

import 'dart:convert';

class MetricsThresholds {
  final int window; // how many recent runs the unreliable flag inspects
  final int manualThreshold; // manual_code_corrections that marks a run "bad"
  final int badRuns; // bad runs within the window that trip the flag
  final int circuitMinRuns; // min adapter runs before its breaker can trip
  final int hallucinationPct; // hallucination-rate % that trips an adapter

  const MetricsThresholds({
    this.window = 5,
    this.manualThreshold = 5,
    this.badRuns = 3,
    this.circuitMinRuns = 5,
    this.hallucinationPct = 20,
  });
}

class AdapterHealth {
  final String adapter;
  final int totalRuns;
  final int badRuns;
  final double rate; // 0..1
  final bool breakerTripped; // disable the adapter
  final bool shouldReset; // re-enable: last `circuitMinRuns` runs all clean
  const AdapterHealth(
    this.adapter,
    this.totalRuns,
    this.badRuns,
    this.rate,
    this.breakerTripped,
    this.shouldReset,
  );

  Map<String, Object?> toJson() => {
    'adapter': adapter,
    'total_runs': totalRuns,
    'bad_runs': badRuns,
    'hallucination_rate_pct': (rate * 100).round(),
    'breaker_tripped': breakerTripped,
    'should_reset': shouldReset,
  };
}

class MetricsSummary {
  final int totalRuns;
  final int windowRuns;
  final int manualBadCount;
  final bool unreliableFlag;
  final List<AdapterHealth> adapters;
  final int malformedLines;

  const MetricsSummary({
    required this.totalRuns,
    required this.windowRuns,
    required this.manualBadCount,
    required this.unreliableFlag,
    required this.adapters,
    required this.malformedLines,
  });

  Map<String, Object?> toJson() => {
    'total_runs': totalRuns,
    'window_runs': windowRuns,
    'manual_bad_count': manualBadCount,
    'unreliable_flag': unreliableFlag,
    'adapters': adapters.map((a) => a.toJson()).toList(),
    if (malformedLines > 0) 'malformed_lines': malformedLines,
  };
}

/// Parse JSONL into a list of entry maps. Malformed lines are skipped but
/// counted (returned separately) — never silently dropped (P1).
({List<Map<String, Object?>> entries, int malformed}) parseHistory(
  String jsonl,
) {
  final entries = <Map<String, Object?>>[];
  var malformed = 0;
  for (final line in const LineSplitter().convert(jsonl)) {
    if (line.trim().isEmpty) continue;
    try {
      final decoded = jsonDecode(line);
      if (decoded is Map<String, Object?>) {
        entries.add(decoded);
      } else {
        malformed++;
      }
    } on FormatException {
      malformed++;
    }
  }
  return (entries: entries, malformed: malformed);
}

MetricsSummary aggregateMetrics(
  List<Map<String, Object?>> entries,
  MetricsThresholds t, {
  int malformedLines = 0,
}) {
  final window = entries.length <= t.window
      ? entries
      : entries.sublist(entries.length - t.window);

  final manualBad = window
      .where((e) => _asInt(e['manual_code_corrections']) >= t.manualThreshold)
      .length;

  // Group window runs by the design-source adapter they used.
  final byAdapter = <String, List<Map<String, Object?>>>{};
  for (final e in window) {
    final adapter = e['design_source_used'];
    if (adapter is String && adapter.isNotEmpty) {
      byAdapter.putIfAbsent(adapter, () => []).add(e);
    }
  }
  final adapters = <AdapterHealth>[];
  byAdapter.forEach((adapter, runs) {
    final bad = runs
        .where((e) => _asInt(e['design_source_hallucinations']) > 0)
        .length;
    final rate = runs.isEmpty ? 0.0 : bad / runs.length;
    final enoughRuns = runs.length >= t.circuitMinRuns;

    // Recovery (auto-reset) takes precedence: if the most recent
    // `circuitMinRuns` runs are all clean, the adapter has recovered — it is
    // NOT tripped (hysteresis), and should be re-enabled if it was disabled.
    final lastN = runs.sublist(
      runs.length - t.circuitMinRuns.clamp(0, runs.length),
    );
    final recentAllClean =
        enoughRuns &&
        lastN.every((e) => _asInt(e['design_source_hallucinations']) == 0);

    final tripped =
        !recentAllClean && enoughRuns && rate > t.hallucinationPct / 100;
    adapters.add(
      AdapterHealth(adapter, runs.length, bad, rate, tripped, recentAllClean),
    );
  });
  adapters.sort((a, b) => a.adapter.compareTo(b.adapter));

  return MetricsSummary(
    totalRuns: entries.length,
    windowRuns: window.length,
    manualBadCount: manualBad,
    unreliableFlag: manualBad >= t.badRuns,
    adapters: adapters,
    malformedLines: malformedLines,
  );
}

int _asInt(Object? v) => v is int ? v : (v is num ? v.toInt() : 0);
