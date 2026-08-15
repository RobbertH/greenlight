import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../prediction/cycle_estimator.dart';
import '../util.dart';
import 'widgets/prediction_panel.dart';

/// The screen you have open while waiting at a red light: one huge tap target,
/// tapped at the exact moment the light turns green.
class RecordScreen extends StatefulWidget {
  final AppState state;

  const RecordScreen({super.key, required this.state});

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  CycleEstimate? _estimate;
  bool _estimating = false;
  List<int> _timestamps = const [];
  int? _lastRecordedMs;
  bool _flash = false;

  @override
  void initState() {
    super.initState();
    // Re-runs on every AppState change, notably the lifecycle-resume merge of
    // widget-recorded taps — otherwise this screen shows stale counts and a
    // prediction that ignores those events.
    widget.state.addListener(_refresh);
    _refresh();
  }

  @override
  void dispose() {
    widget.state.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _refresh() async {
    final light = widget.state.activeLight;
    if (light == null) return;
    setState(() => _estimating = true);
    final ts = await widget.state.repo.eventTimestamps(light.id);
    final est = await compute(estimateCycle, ts);
    if (!mounted) return;
    setState(() {
      _timestamps = ts;
      _estimate = est;
      _estimating = false;
    });
  }

  Future<void> _record(PointerDownEvent _) async {
    // Capture the moment of finger contact before anything else runs.
    final tsMs = DateTime.now().millisecondsSinceEpoch;
    HapticFeedback.heavyImpact();
    setState(() {
      _flash = true;
      _lastRecordedMs = tsMs;
    });
    Future.delayed(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _flash = false);
    });
    // recordGreen notifies AppState listeners, which triggers _refresh.
    await widget.state.recordGreen(tsMs);
  }

  @override
  Widget build(BuildContext context) {
    final light = widget.state.activeLight;
    if (light == null) {
      // Can happen when the widget deep-links here before a light exists.
      return Scaffold(
        appBar: AppBar(title: const Text('Record')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'No light selected yet.\nGo back to the map, long-press to add '
              'a light and tap its pin to select it.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final today = _todayCount();
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(light.name),
            Text(
              '${_timestamps.length} recorded · $today today',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          PredictionPanel(
            estimate: _estimate,
            eventCount: _timestamps.length,
            estimating: _estimating,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Listener(
                onPointerDown: _record,
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  decoration: BoxDecoration(
                    color: _flash ? Colors.green : Colors.green.shade700,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.touch_app,
                            size: 72, color: Colors.white),
                        const SizedBox(height: 12),
                        const Text(
                          'TAP WHEN GREEN',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _lastRecordedMs == null
                              ? 'Tap the moment the light turns green'
                              : 'Recorded at ${fmtTime(_lastRecordedMs!)} ✓',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  int _todayCount() {
    final now = DateTime.now();
    final midnight =
        DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    return _timestamps.where((t) => t >= midnight).length;
  }
}
