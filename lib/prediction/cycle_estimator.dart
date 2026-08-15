// Pure Dart — no Flutter imports, so it runs in plain unit tests and via
// compute() in an isolate.
//
// Model: a fixed-cycle traffic light turns green at t ≡ φ (mod C). Recorded
// green-onset timestamps then concentrate around one phase angle when folded
// at the true cycle length. We scan candidate frequencies f = 1/C and score
// each by the mean resultant length R(f) = |Σ e^(i·2π·s_j·f)| / n, the
// standard circular-statistics concentration measure (this is epoch folding).
import 'dart:math' as math;

enum ConfidenceTier { high, medium, insufficient }

class CycleEstimate {
  /// Estimated cycle length C in seconds.
  final double cycleSeconds;

  /// Phase φ: seconds after [anchorMs] of the cluster center.
  final double phaseSeconds;

  /// Mean resultant length at the chosen frequency, on the full window (0..1).
  final double resultantR;

  /// Number of events used after windowing and dedupe.
  final int n;

  /// Circular standard deviation mapped to seconds.
  final double sigmaSeconds;

  /// Rayleigh-test p-value, Bonferroni-corrected for the scanned frequencies.
  final double pValue;

  /// Epoch ms of the first event used; phase is relative to this.
  final int anchorMs;

  final ConfidenceTier tier;

  const CycleEstimate({
    required this.cycleSeconds,
    required this.phaseSeconds,
    required this.resultantR,
    required this.n,
    required this.sigmaSeconds,
    required this.pValue,
    required this.anchorMs,
    required this.tier,
  });

  /// The first predicted green strictly after [nowMs].
  int nextGreenMs(int nowMs) {
    final cMs = cycleSeconds * 1000;
    final baseMs = anchorMs + phaseSeconds * 1000;
    var next = baseMs + ((nowMs - baseMs) / cMs).ceil() * cMs;
    if (next <= nowMs) next += cMs;
    return next.round();
  }
}

class CycleEstimator {
  static const double minCycleS = 30;
  static const double maxCycleS = 200;
  static const int minEvents = 5;
  static const int maxEvents = 300;
  static const int maxAgeDays = 30;

  /// Taps closer together than this are double-taps, not separate cycles.
  static const double dedupeGapS = 15;

  /// A 48 h stage-1 window is only trustworthy with enough events: with n≈5-8
  /// the coarse grid's ~10³ independent frequencies make a spurious near-max
  /// peak at smaller f likely, and the largest-C tie-break then locks onto
  /// noise the narrow stage-2 band cannot escape.
  static const int stage1MinEvents = 20;

  /// Grid resolution: 8 samples across the R(f) peak (peak width ≈ 1/span).
  static const int _samplesPerPeak = 8;

  /// Cost ceiling for the coarse scan, in (grid steps × events) trig ops.
  static const int _maxScanOps = 60000000;

  /// Estimates the cycle from ascending epoch-ms green onsets.
  /// Returns null when there is not enough data to even attempt a fit.
  static CycleEstimate? estimate(List<int> tsMs, {int? nowMs}) {
    if (tsMs.isEmpty) return null;
    final now = nowMs ?? tsMs.last;

    // Window: recent events only, so light reprogramming ages out.
    final cutoff = now - maxAgeDays * 86400000;
    var kept = [
      for (final t in tsMs)
        if (t >= cutoff && t <= now) t
    ];
    if (kept.length > maxEvents) {
      kept = kept.sublist(kept.length - maxEvents);
    }

    // Dedupe double-taps: keep the first tap of any burst (closest to the
    // actual transition; later taps are corrections/accidents).
    final deduped = <int>[];
    for (final t in kept) {
      if (deduped.isEmpty || (t - deduped.last) / 1000 >= dedupeGapS) {
        deduped.add(t);
      }
    }
    if (deduped.length < minEvents) return null;

    final anchorMs = deduped.first;
    final s = [for (final t in deduped) (t - anchorMs) / 1000.0];
    final spanFull = s.last - s.first;
    if (spanFull < 2 * minCycleS) return null;

    const fMin = 1 / maxCycleS;
    const fMax = 1 / minCycleS;

    // Stage 1 — coarse scan on a window whose span keeps the grid affordable.
    // Prefer the last 48 h (dense, cheap, and R is origin-invariant); fall
    // back to progressively shorter tails until the op budget fits.
    final stage1 = _pickScanWindow(s, spanFull);
    final coarse = _scan(stage1, fMin, fMax,
        df: 1 / (_samplesPerPeak * _spanOf(stage1)));
    if (coarse == null) return null;

    // Divisor tie-break: perfect folds also cluster at C/2, C/3, … (larger f).
    // Among local peaks within 2% of the max, take the SMALLEST f = largest C.
    final fCoarse = _smallestNearMaxPeak(coarse);

    // Stage 2 — refine around the coarse peak using the full window's
    // resolution, then parabolic interpolation for sub-grid precision.
    final df2 = 1 / (_samplesPerPeak * spanFull);
    final band = 2 / (_samplesPerPeak * _spanOf(stage1));
    final fine = _scan(s, math.max(fMin, fCoarse - band),
            math.min(fMax, fCoarse + band),
            df: df2) ??
        coarse;
    var fBest = _parabolicPeak(fine);

    // Final statistics on the full window at the refined frequency.
    var sumCos = 0.0, sumSin = 0.0;
    for (final sj in s) {
      final a = 2 * math.pi * ((sj * fBest) % 1.0);
      sumCos += math.cos(a);
      sumSin += math.sin(a);
    }
    final n = s.length;
    final r = math.sqrt(sumCos * sumCos + sumSin * sumSin) / n;
    final c = 1 / fBest;
    final meanAngle = math.atan2(sumSin, sumCos);
    final phase = ((meanAngle / (2 * math.pi)) * c) % c;

    final sigma =
        r >= 1 ? 0.0 : math.sqrt(-2 * math.log(r)) * c / (2 * math.pi);
    final z = n * r * r;
    // Bonferroni over the number of independent frequencies in the scan range
    // (independent spacing ≈ 1/span).
    final m = math.max(1, ((fMax - fMin) * spanFull).round());
    final p = math.min(1.0, m * math.exp(-z));

    final tier = p > 0.01
        ? ConfidenceTier.insufficient
        : (p < 1e-4 && n >= 10 && sigma < 3)
            ? ConfidenceTier.high
            : ConfidenceTier.medium;

    return CycleEstimate(
      cycleSeconds: c,
      phaseSeconds: phase < 0 ? phase + c : phase,
      resultantR: r,
      n: n,
      sigmaSeconds: sigma,
      pValue: p,
      anchorMs: anchorMs,
      tier: tier,
    );
  }

  static double _spanOf(List<double> s) => s.last - s.first;

  /// The stage-1 window: last 48 h if it holds enough events, else the
  /// longest tail of events that fits the op budget.
  static List<double> _pickScanWindow(List<double> s, double spanFull) {
    final tail48 = _tailSince(s, s.last - 172800);
    if (tail48.length >= stage1MinEvents && _spanOf(tail48) >= 2 * minCycleS) {
      return tail48;
    }
    var window = s;
    while (true) {
      final steps =
          (1 / minCycleS - 1 / maxCycleS) * _samplesPerPeak * _spanOf(window);
      if (steps * window.length <= _maxScanOps || _spanOf(window) < 4 * minCycleS) {
        return window;
      }
      window = _tailSince(s, s.last - _spanOf(window) / 2);
      if (window.length < minEvents) return s; // sparse: steps*n stays small
    }
  }

  static List<double> _tailSince(List<double> s, double from) =>
      [for (final v in s) if (v >= from) v];

  /// Scans [fLo, fHi] at spacing [df]; returns grid frequencies and R values.
  static _ScanResult? _scan(List<double> s, double fLo, double fHi,
      {required double df}) {
    if (fHi <= fLo || df <= 0) return null;
    final steps = ((fHi - fLo) / df).ceil() + 1;
    if (steps < 3) return null;
    final fs = List<double>.filled(steps, 0);
    final rs = List<double>.filled(steps, 0);
    for (var i = 0; i < steps; i++) {
      final f = fLo + i * df;
      var sumCos = 0.0, sumSin = 0.0;
      for (final sj in s) {
        final a = 2 * math.pi * ((sj * f) % 1.0);
        sumCos += math.cos(a);
        sumSin += math.sin(a);
      }
      fs[i] = f;
      rs[i] = math.sqrt(sumCos * sumCos + sumSin * sumSin) / s.length;
    }
    return _ScanResult(fs, rs);
  }

  static double _smallestNearMaxPeak(_ScanResult scan) {
    var rMax = 0.0;
    for (final r in scan.rs) {
      if (r > rMax) rMax = r;
    }
    final threshold = 0.98 * rMax;
    for (var i = 1; i < scan.rs.length - 1; i++) {
      if (scan.rs[i] >= threshold &&
          scan.rs[i] >= scan.rs[i - 1] &&
          scan.rs[i] >= scan.rs[i + 1]) {
        return scan.fs[i];
      }
    }
    // No interior local max (monotone edge case): take the global max.
    var best = 0;
    for (var i = 0; i < scan.rs.length; i++) {
      if (scan.rs[i] > scan.rs[best]) best = i;
    }
    return scan.fs[best];
  }

  /// Refines the grid peak with a parabola through its three central points.
  static double _parabolicPeak(_ScanResult scan) {
    var best = 0;
    for (var i = 0; i < scan.rs.length; i++) {
      if (scan.rs[i] > scan.rs[best]) best = i;
    }
    if (best == 0 || best == scan.rs.length - 1) return scan.fs[best];
    final r1 = scan.rs[best - 1], r2 = scan.rs[best], r3 = scan.rs[best + 1];
    final denom = r1 - 2 * r2 + r3;
    if (denom.abs() < 1e-12) return scan.fs[best];
    final delta = (0.5 * (r1 - r3) / denom).clamp(-1.0, 1.0);
    return scan.fs[best] + delta * (scan.fs[1] - scan.fs[0]);
  }
}

class _ScanResult {
  final List<double> fs;
  final List<double> rs;
  _ScanResult(this.fs, this.rs);
}

/// Top-level entry point for `compute()`. Anchors the recency window to real
/// wall-clock time so stale data ages out (a months-old fit must not produce
/// a confident countdown extrapolated thousands of cycles forward).
CycleEstimate? estimateCycle(List<int> tsMs) => CycleEstimator.estimate(
      tsMs,
      nowMs: DateTime.now().millisecondsSinceEpoch,
    );
