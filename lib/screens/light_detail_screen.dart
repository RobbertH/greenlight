import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../data/light_repository.dart';
import '../prediction/cycle_estimator.dart';
import '../util.dart';
import 'widgets/prediction_panel.dart';

class LightDetailScreen extends StatefulWidget {
  final AppState state;
  final Light light;

  const LightDetailScreen(
      {super.key, required this.state, required this.light});

  @override
  State<LightDetailScreen> createState() => _LightDetailScreenState();
}

class _LightDetailScreenState extends State<LightDetailScreen> {
  List<LightEvent> _events = const [];
  CycleEstimate? _estimate;
  bool _loading = true;
  int? _greenS;

  LightRepository get _repo => widget.state.repo;

  int get _outlierCount => _events.where(_isOutlier).length;

  /// The odd one out: doesn't fit the detected cadence. Events older than the
  /// estimator's window aged out of the fit, so residuals there mean nothing.
  bool _isOutlier(LightEvent e) {
    final est = _estimate;
    if (est == null) return false;
    final cutoff = DateTime.now().millisecondsSinceEpoch -
        CycleEstimator.maxAgeDays * 86400000;
    if (e.tsMs < cutoff) return false;
    return est.isOutlier(e.tsMs);
  }

  Widget _eventTile(LightEvent e) {
    final odd = _isOutlier(e);
    const orange = Colors.orange;
    return ListTile(
      dense: true,
      leading: Icon(
        odd
            ? Icons.warning_amber_rounded
            : e.source == 'widget'
                ? Icons.widgets_outlined
                : Icons.smartphone,
        size: 20,
        color: odd ? orange : null,
      ),
      title: Text(fmtDateTime(e.tsMs),
          style: odd ? const TextStyle(color: orange) : null),
      subtitle: Text(odd
          ? 'via ${e.source} · off the cadence by '
              '${_estimate!.residualSeconds(e.tsMs).abs().toStringAsFixed(1)} s'
          : 'via ${e.source}'),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline, size: 20),
        tooltip: 'Delete this event',
        onPressed: () async {
          await widget.state.deleteEvent(e.id, lightId: e.lightId);
          await _load();
        },
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _greenS = widget.light.greenS;
    _load();
  }

  Future<void> _load() async {
    final events = await _repo.eventsForLight(widget.light.id);
    final ts = await _repo.eventTimestamps(widget.light.id);
    final est = await compute(estimateCycle, ts);
    if (!mounted) return;
    setState(() {
      _events = events;
      _estimate = est;
      _loading = false;
    });
  }

  Future<void> _copy(String what, String content) async {
    await Clipboard.setData(ClipboardData(text: content));
    _snack('$what copied to clipboard (${_events.length} events)');
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Debug-only: writes a synthetic 90 s cycle into this light so the whole
  /// prediction path can be validated end-to-end without standing at a light.
  Future<void> _seedSynthetic() async {
    final rng = Random();
    const cycleS = 90.0;
    final phaseS = rng.nextDouble() * cycleS;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final t0Ms = nowMs - 3 * 86400000;
    final totalCycles = (3 * 86400 / cycleS).floor();
    final ks = <int>{};
    while (ks.length < 40) {
      ks.add(rng.nextInt(totalCycles));
    }
    var inserted = 0;
    for (final k in ks.toList()..sort()) {
      final delay = 0.5 + rng.nextDouble() * 0.4 - 0.2; // ~N(0.5, …)-ish
      final ts = t0Ms + ((phaseS + k * cycleS + delay) * 1000).round();
      if (ts >= nowMs) continue;
      if (await _repo.recordEvent(widget.light.id, ts, 'app')) inserted++;
    }
    await widget.state.syncWithWidget();
    await widget.state.load();
    await _load();
    _snack('Seeded $inserted synthetic events (90 s cycle, phase '
        '${phaseS.toStringAsFixed(1)} s)');
  }

  Future<void> _deleteLight() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete “${widget.light.name}”?'),
        content: Text('This removes the light and its ${_events.length} '
            'recorded events. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton.tonal(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await widget.state.removeLight(widget.light);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.light.name),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) => switch (v) {
              'csv' => _copy('CSV', _repo.eventsToCsv(widget.light, _events)),
              'json' =>
                _copy('JSON', _repo.eventsToJson(widget.light, _events)),
              'seed' => _seedSynthetic(),
              'delete' => _deleteLight(),
              _ => null,
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                  value: 'csv', child: Text('Copy events as CSV')),
              const PopupMenuItem(
                  value: 'json', child: Text('Copy events as JSON')),
              if (kDebugMode)
                const PopupMenuItem(
                    value: 'seed',
                    child: Text('DEBUG: seed 90 s test cycle')),
              const PopupMenuDivider(),
              const PopupMenuItem(
                  value: 'delete', child: Text('Delete light…')),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                PredictionPanel(
                    estimate: _estimate, eventCount: _events.length),
                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Data', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Text('${widget.light.type.label} light'),
                        Text('${_events.length} green transitions recorded'),
                        if (_events.isNotEmpty) ...[
                          Text('First: ${fmtDateTime(_events.last.tsMs)}'),
                          Text('Latest: ${fmtDateTime(_events.first.tsMs)}'),
                        ],
                        if (_estimate != null) ...[
                          const SizedBox(height: 8),
                          Text('Fit: R=${_estimate!.resultantR.toStringAsFixed(3)} '
                              '· p=${_estimate!.pValue.toStringAsExponential(1)} '
                              '· used n=${_estimate!.n}'),
                        ],
                        if (_outlierCount > 0) ...[
                          const SizedBox(height: 8),
                          Text(
                            "$_outlierCount record${_outlierCount == 1 ? '' : 's'} "
                            "(orange below) don't fit the cadence — delete "
                            'them if they were mistaps.',
                            style: const TextStyle(color: Colors.orange),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Card(
                  margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Settings', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Text(_greenS == null
                            ? 'Green lasts ~${Light.defaultGreenS} s '
                                '(default — adjust to match this light)'
                            : 'Green lasts ~$_greenS s'),
                        Slider(
                          value: (_greenS ?? Light.defaultGreenS).toDouble(),
                          min: 3,
                          max: 120,
                          divisions: 117,
                          label: '${_greenS ?? Light.defaultGreenS} s',
                          onChanged: (v) =>
                              setState(() => _greenS = v.round()),
                          onChangeEnd: (v) => widget.state
                              .setGreenSeconds(widget.light, v.round()),
                        ),
                        Text(
                          'Drives the map pin: it shows green for this long '
                          'after each predicted onset, red for the rest of '
                          'the cycle.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                for (final e in _events) _eventTile(e),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}
