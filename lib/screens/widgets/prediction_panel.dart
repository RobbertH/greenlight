import 'dart:async';

import 'package:flutter/material.dart';

import '../../prediction/cycle_estimator.dart';
import '../../util.dart';

/// Shows the state of the cycle prediction for one light: a live countdown to
/// the predicted next green when the estimate is confident, otherwise what is
/// still missing. Refreshes itself once a second for the countdown.
class PredictionPanel extends StatefulWidget {
  final CycleEstimate? estimate;
  final int eventCount;
  final bool estimating;

  const PredictionPanel({
    super.key,
    required this.estimate,
    required this.eventCount,
    this.estimating = false,
  });

  @override
  State<PredictionPanel> createState() => _PredictionPanelState();
}

class _PredictionPanelState extends State<PredictionPanel> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final est = widget.estimate;

    Widget body;
    if (widget.estimating && est == null) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: LinearProgressIndicator(),
      );
    } else if (est == null) {
      body = Text(
        widget.eventCount < 5
            ? 'No cycle yet — ${widget.eventCount} of 5 minimum records. '
                'Tap each time this light turns green.'
            : 'Not enough spread in the data yet — keep recording over a few '
                'more cycles.',
        style: theme.textTheme.bodyMedium,
      );
    } else if (est.tier == ConfidenceTier.insufficient) {
      body = Text(
        'No reliable cycle detected yet (${est.n} records). Either more data '
        'is needed, or this light is not on a fixed cycle.',
        style: theme.textTheme.bodyMedium,
      );
    } else {
      final now = DateTime.now().millisecondsSinceEpoch;
      final remaining = est.nextGreenMs(now) - now;
      final aboutNow = remaining <= 2000;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                aboutNow ? 'GREEN' : fmtCountdown(remaining),
                style: theme.textTheme.displaySmall!.copyWith(
                  fontWeight: FontWeight.bold,
                  color: aboutNow
                      ? Colors.green
                      : theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 8),
              Text(aboutNow ? 'about now 🚦' : 'until predicted green',
                  style: theme.textTheme.bodyMedium),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _chip(context,
                  'cycle ${est.cycleSeconds.toStringAsFixed(1)} s'),
              _chip(context, '±${est.sigmaSeconds.toStringAsFixed(1)} s'),
              _chip(context, '${est.n} records'),
              _chip(
                context,
                est.tier == ConfidenceTier.high
                    ? 'high confidence'
                    : 'medium confidence',
                emphasized: est.tier == ConfidenceTier.high,
              ),
            ],
          ),
        ],
      );
    }

    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.query_stats,
                color: theme.colorScheme.primary, size: 32),
            const SizedBox(width: 12),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, String label, {bool emphasized = false}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: emphasized ? scheme.primaryContainer : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelMedium),
    );
  }
}
