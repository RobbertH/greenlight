import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:greenlight/prediction/cycle_estimator.dart';

const t0Ms = 1755200000000; // fixed arbitrary epoch anchor

/// True greens happen at t0 + phase + k*cycle (seconds). A "user" records a
/// random subset of cycles, each with Gaussian reaction delay. Deterministic
/// via the seed.
List<int> synthetic({
  required double cycleS,
  required double phaseS,
  required int days,
  required int samples,
  required int seed,
  double meanDelayS = 0.5,
  double sdDelayS = 0.25,
}) {
  final rng = Random(seed);
  final totalCycles = (days * 86400 / cycleS).floor();
  final ks = <int>{};
  while (ks.length < samples) {
    ks.add(rng.nextInt(totalCycles));
  }
  final sorted = ks.toList()..sort();
  return [
    for (final k in sorted)
      t0Ms +
          ((phaseS +
                      k * cycleS +
                      _gauss(rng, meanDelayS, sdDelayS).clamp(0.05, 2.0)) *
                  1000)
              .round()
  ];
}

double _gauss(Random rng, double mean, double sd) {
  final u1 = rng.nextDouble().clamp(1e-12, 1.0);
  final u2 = rng.nextDouble();
  return mean + sd * sqrt(-2 * log(u1)) * cos(2 * pi * u2);
}

/// Ground-truth next green strictly after nowMs.
int actualNextGreen(double cycleS, double phaseS, int nowMs) {
  final baseMs = t0Ms + phaseS * 1000;
  final cMs = cycleS * 1000;
  var next = baseMs + ((nowMs - baseMs) / cMs).ceil() * cMs;
  if (next <= nowMs) next += cMs;
  return next.round();
}

void main() {
  test('recovers a 90 s cycle with reaction jitter over 3 days', () {
    final ts = synthetic(cycleS: 90, phaseS: 17, days: 3, samples: 60, seed: 42);
    final est = CycleEstimator.estimate(ts)!;

    expect((est.cycleSeconds - 90).abs(), lessThan(0.1),
        reason: 'C=${est.cycleSeconds}');
    expect(est.tier, isNot(ConfidenceTier.insufficient));
    expect(est.resultantR, greaterThan(0.9));

    // Prediction: mid-cycle, 40 s after the last recorded event.
    final now = ts.last + 40000;
    final predicted = est.nextGreenMs(now);
    final actual = actualNextGreen(90, 17, now);
    expect(predicted, greaterThan(now));
    expect((predicted - actual).abs(), lessThan(1500),
        reason:
            'predicted=$predicted actual=$actual diff=${predicted - actual}ms '
            '(≈+500 ms reaction-delay bias is expected)');
  });

  test('recovers a non-integer 62.5 s cycle', () {
    final ts =
        synthetic(cycleS: 62.5, phaseS: 31, days: 3, samples: 50, seed: 7);
    final est = CycleEstimator.estimate(ts)!;
    expect((est.cycleSeconds - 62.5).abs(), lessThan(0.1),
        reason: 'C=${est.cycleSeconds}');
  });

  test('divisor trap: picks 90, not 45', () {
    final ts = synthetic(
        cycleS: 90,
        phaseS: 10,
        days: 3,
        samples: 60,
        seed: 3,
        meanDelayS: 0.3,
        sdDelayS: 0.15);
    final est = CycleEstimator.estimate(ts)!;
    expect(est.cycleSeconds, greaterThan(80),
        reason: 'must not lock onto the C/2 divisor (C=${est.cycleSeconds})');
    expect((est.cycleSeconds - 90).abs(), lessThan(0.1));
  });

  test('survives a multi-day gap in the data', () {
    final all =
        synthetic(cycleS: 90, phaseS: 17, days: 3, samples: 80, seed: 11);
    // Drop everything in the middle day.
    final gapStart = t0Ms + 86400000;
    final gapEnd = t0Ms + 2 * 86400000;
    final ts = [
      for (final t in all)
        if (t < gapStart || t >= gapEnd) t
    ];
    expect(ts.length, greaterThan(20));
    final est = CycleEstimator.estimate(ts)!;
    expect((est.cycleSeconds - 90).abs(), lessThan(0.1),
        reason: 'C=${est.cycleSeconds}');
  });

  test('uniform-random timestamps yield no confident cycle', () {
    final rng = Random(99);
    final raw = [
      for (var i = 0; i < 60; i++) t0Ms + rng.nextInt(2 * 86400000)
    ]..sort();
    final est = CycleEstimator.estimate(raw);
    expect(est == null || est.tier == ConfidenceTier.insufficient, isTrue,
        reason: est == null
            ? 'null is fine'
            : 'p=${est.pValue} R=${est.resultantR} C=${est.cycleSeconds}');
  });

  test('too few events returns null', () {
    final ts = synthetic(cycleS: 90, phaseS: 17, days: 1, samples: 4, seed: 1);
    expect(CycleEstimator.estimate(ts), isNull);
  });

  test('span shorter than two minimum cycles returns null', () {
    final ts = [for (var i = 0; i < 6; i++) t0Ms + i * 9000];
    // 6 events, 45 s span — under the 60 s floor even before dedupe.
    expect(CycleEstimator.estimate(ts), isNull);
  });

  test('double-taps within 15 s are deduped, cycle still recovered', () {
    final base =
        synthetic(cycleS: 90, phaseS: 17, days: 3, samples: 50, seed: 5);
    final withDoubles = <int>[];
    for (final t in base) {
      withDoubles.add(t);
      withDoubles.add(t + 800); // accidental second tap
    }
    final est = CycleEstimator.estimate(withDoubles)!;
    expect(est.n, base.length, reason: 'doubles removed');
    expect((est.cycleSeconds - 90).abs(), lessThan(0.1));
  });

  test('prediction lands within one cycle of now', () {
    final ts = synthetic(cycleS: 75, phaseS: 5, days: 2, samples: 40, seed: 13);
    final est = CycleEstimator.estimate(ts)!;
    final now = ts.last + 123456;
    final next = est.nextGreenMs(now);
    expect(next, greaterThan(now));
    expect(next - now, lessThanOrEqualTo((est.cycleSeconds * 1000).round() + 1));
  });
}
