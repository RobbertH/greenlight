import 'package:flutter/foundation.dart';

import 'data/light_repository.dart';
import 'data/widget_sync.dart';

class AppState extends ChangeNotifier {
  final LightRepository repo;

  List<Light> lights = [];
  Map<int, int> eventCounts = {};
  Light? activeLight;

  AppState(this.repo);

  Future<void> load() async {
    lights = await repo.getLights();
    eventCounts = await repo.eventCountsByLight();
    activeLight = _byId(await WidgetSync.getActiveLightId());
    notifyListeners();
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

  Future<Light> addLight(String name, double lat, double lng) async {
    final light = await repo.createLight(name, lat, lng);
    lights = await repo.getLights();
    notifyListeners();
    return light;
  }

  Future<void> removeLight(Light light) async {
    await repo.deleteLight(light.id);
    lights = await repo.getLights();
    eventCounts = await repo.eventCountsByLight();
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
    notifyListeners();
    await WidgetSync.pushWidgetState(repo);
    return inserted;
  }

  /// Merges taps recorded by the home-screen widget and refreshes its display.
  Future<int> syncWithWidget() async {
    final merged = await WidgetSync.mergePendingEvents(repo);
    await WidgetSync.pushWidgetState(repo);
    if (merged > 0) {
      eventCounts = await repo.eventCountsByLight();
      notifyListeners();
    }
    return merged;
  }
}
