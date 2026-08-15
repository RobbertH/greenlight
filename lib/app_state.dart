import 'package:flutter/foundation.dart';

import 'data/light_repository.dart';
import 'data/widget_sync.dart';
import 'prediction/cycle_estimator.dart';

class AppState extends ChangeNotifier {
  final LightRepository repo;

  List<Light> lights = [];
  Map<int, int> eventCounts = {};

  /// Latest cycle fit per light id (null = not enough data). Kept here so the
  /// map can color markers and tick countdowns without re-running the
  /// estimator every frame.
  Map<int, CycleEstimate?> estimates = {};
  Light? activeLight;

  AppState(this.repo);

  Future<void> load() async {
    lights = await repo.getLights();
    eventCounts = await repo.eventCountsByLight();
    activeLight = _byId(await WidgetSync.getActiveLightId());
    await _refreshEstimates();
    notifyListeners();
  }

  /// Re-fits the cycle estimate for one light (or all of them) off the UI
  /// thread. Lights below the estimator's minimum are skipped cheaply.
  Future<void> _refreshEstimates({int? onlyLightId}) async {
    final next = Map<int, CycleEstimate?>.of(estimates)
      ..removeWhere((id, _) => !lights.any((l) => l.id == id));
    for (final l in lights) {
      if (onlyLightId != null && l.id != onlyLightId) continue;
      if ((eventCounts[l.id] ?? 0) < CycleEstimator.minEvents) {
        next[l.id] = null;
        continue;
      }
      next[l.id] = await compute(estimateCycle, await repo.eventTimestamps(l.id));
    }
    estimates = next;
  }

  Light? _byId(int? id) {
    if (id == null) return null;
    for (final l in lights) {
      if (l.id == id) return l;
    }
    return null;
  }

  Future<void> selectLight(Light light) async {
    activeLight = light;
    notifyListeners();
    await WidgetSync.setActiveLight(repo, light);
  }

  Future<Light> addLight(String name, double lat, double lng,
      {LightType type = LightType.pedestrian}) async {
    final light = await repo.createLight(name, lat, lng, type: type);
    lights = await repo.getLights();
    notifyListeners();
    return light;
  }

  /// Persists how long [light] stays green; null reverts to the default.
  Future<void> setGreenSeconds(Light light, int? seconds) async {
    await repo.setGreenSeconds(light.id, seconds);
    lights = await repo.getLights();
    if (activeLight?.id == light.id) activeLight = _byId(light.id);
    notifyListeners();
  }

  Future<void> removeLight(Light light) async {
    await repo.deleteLight(light.id);
    lights = await repo.getLights();
    eventCounts = await repo.eventCountsByLight();
    estimates.remove(light.id);
    if (activeLight?.id == light.id) {
      activeLight = null;
      await WidgetSync.clearActiveLight();
    }
    notifyListeners();
  }

  /// Records an in-app green transition for the active light. [tsMs] must be
  /// captured by the caller at pointer-down, before any awaits.
  Future<bool> recordGreen(int tsMs) async {
    final light = activeLight;
    if (light == null) return false;
    final inserted = await repo.recordEvent(light.id, tsMs, 'app');
    eventCounts = await repo.eventCountsByLight();
    await _refreshEstimates(onlyLightId: light.id);
    notifyListeners();
    await WidgetSync.pushWidgetState(repo);
    return inserted;
  }

  Future<void> deleteEvent(int eventId, {int? lightId}) async {
    await repo.deleteEvent(eventId);
    eventCounts = await repo.eventCountsByLight();
    await _refreshEstimates(onlyLightId: lightId);
    notifyListeners();
    // Deleting one of today's events must also correct the widget's counts.
    await WidgetSync.pushWidgetState(repo);
  }

  /// Merges taps recorded by the home-screen widget and refreshes its display.
  Future<int> syncWithWidget() async {
    final merged = await WidgetSync.mergePendingEvents(repo);
    await WidgetSync.pushWidgetState(repo);
    if (merged > 0) {
      eventCounts = await repo.eventCountsByLight();
      await _refreshEstimates();
      notifyListeners();
    }
    return merged;
  }
}
