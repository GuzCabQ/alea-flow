// Unit tests for the pipeline metrics aggregator — the deterministic
// circuit-breaker arithmetic that replaces the prose in /pipeline-feedback.

import 'package:alea_flow/src/core/metrics/metrics_aggregator.dart';
import 'package:test/test.dart';

void main() {
  Map<String, Object?> run({
    int manual = 0,
    String? adapter,
    int hallucinations = 0,
  }) => {
    'manual_code_corrections': manual,
    'design_source_used': adapter,
    'design_source_hallucinations': hallucinations,
  };

  group('aggregateMetrics — unreliable flag', () {
    const t = MetricsThresholds(); // window 5, manual_threshold 5, bad_runs 3

    test('trips when >= bad_runs recent runs are bad', () {
      final entries = [
        run(manual: 6),
        run(manual: 7),
        run(manual: 5),
        run(manual: 0),
      ];
      final s = aggregateMetrics(entries, t);
      expect(s.manualBadCount, 3);
      expect(s.unreliableFlag, isTrue);
    });

    test('stays off below the threshold count', () {
      final entries = [run(manual: 6), run(manual: 6), run(manual: 0)];
      final s = aggregateMetrics(entries, t);
      expect(s.manualBadCount, 2);
      expect(s.unreliableFlag, isFalse);
    });

    test('only inspects the last `window` runs', () {
      // 3 old bad runs fall outside a window of 2 newest good runs.
      final entries = [
        run(manual: 9),
        run(manual: 9),
        run(manual: 9),
        run(manual: 0),
        run(manual: 0),
      ];
      final s = aggregateMetrics(entries, const MetricsThresholds(window: 2));
      expect(s.windowRuns, 2);
      expect(s.unreliableFlag, isFalse);
    });
  });

  group('aggregateMetrics — adapter hallucination breaker', () {
    const t = MetricsThresholds(circuitMinRuns: 3, hallucinationPct: 20);

    test('trips when rate exceeds the threshold and min runs met', () {
      final entries = [
        run(adapter: 'figma', hallucinations: 1),
        run(adapter: 'figma', hallucinations: 1),
        run(adapter: 'figma', hallucinations: 0),
      ];
      final s = aggregateMetrics(entries, t);
      final figma = s.adapters.singleWhere((a) => a.adapter == 'figma');
      expect(figma.totalRuns, 3);
      expect(figma.badRuns, 2);
      expect(figma.breakerTripped, isTrue); // 67% > 20%
    });

    test('does not trip below min runs even at 100% rate', () {
      final entries = [
        run(adapter: 'figma', hallucinations: 1),
        run(adapter: 'figma', hallucinations: 1),
      ];
      final s = aggregateMetrics(entries, t);
      final figma = s.adapters.singleWhere((a) => a.adapter == 'figma');
      expect(figma.breakerTripped, isFalse); // only 2 runs < circuitMinRuns 3
      expect(figma.shouldReset, isFalse);
    });

    test('auto-reset: last circuitMinRuns all clean → reset, not tripped', () {
      // Overall rate 25% (> 20%), but the last 3 runs are clean → recovery
      // takes precedence (hysteresis): not tripped, should re-enable.
      final entries = [
        run(adapter: 'figma', hallucinations: 1),
        run(adapter: 'figma', hallucinations: 0),
        run(adapter: 'figma', hallucinations: 0),
        run(adapter: 'figma', hallucinations: 0),
      ];
      final s = aggregateMetrics(entries, t);
      final figma = s.adapters.singleWhere((a) => a.adapter == 'figma');
      expect(figma.shouldReset, isTrue);
      expect(figma.breakerTripped, isFalse);
    });

    test('reset and trip are mutually exclusive', () {
      final entries = [
        run(adapter: 'figma', hallucinations: 1),
        run(adapter: 'figma', hallucinations: 1),
        run(adapter: 'figma', hallucinations: 0),
      ];
      final s = aggregateMetrics(entries, t);
      final figma = s.adapters.singleWhere((a) => a.adapter == 'figma');
      expect(figma.breakerTripped && figma.shouldReset, isFalse);
    });
  });

  group('parseHistory', () {
    test('parses JSONL and counts malformed lines (not silently dropped)', () {
      const jsonl =
          '{"manual_code_corrections":1}\n'
          'not json\n'
          '\n'
          '{"manual_code_corrections":2}\n';
      final r = parseHistory(jsonl);
      expect(r.entries, hasLength(2));
      expect(r.malformed, 1);
    });
  });
}
