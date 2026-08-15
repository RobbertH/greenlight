import 'dart:convert';

import 'package:home_widget/home_widget.dart';

import '../constants.dart';
import 'light_repository.dart';

/// Bridges SQLite with the shared key-value store the native home-screen
/// widgets read and write. The widget records taps 100% natively (no Dart
/// engine) by appending `{lightId, ts}` to the [kPendingEvents] JSON array;
/// this class merges that queue into SQLite and pushes display state back.
class WidgetSync {
  // All kv access is best-effort: a failure here must never take the app down
  // (e.g. iOS before the App Group entitlement exists, or during tests).
  static Future<T?> _get<T>(String key) async {
    try {
      return await HomeWidget.getWidgetData<T>(key);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _set(String key, Object? value) async {
    try {
      await HomeWidget.saveWidgetData(key, value);
    } catch (_) {}
  }

  /// A fresh install must not inherit another install's widget state: on iOS
  /// the App Group container can outlive an uninstall, leaving a stale queue
  /// and active-light id that would otherwise merge into (or activate) the
  /// newly seeded lights, whose autoincrement ids restart at 1.
  static Future<void> resetForFreshInstall() async {
    await _set(kPendingEvents, '[]');
    await clearActiveLight();
  }

  static Future<int?> getActiveLightId() async {
    final s = await _get<String>(kActiveLightId);
    return s == null ? null : int.tryParse(s);
  }

  static Future<void> setActiveLight(LightRepository repo, Light light) async {
    await _set(kActiveLightId, light.id.toString());
    await _set(kActiveLightName, light.name);
    await pushWidgetState(repo);
  }

  static Future<void> clearActiveLight() async {
    await _set(kActiveLightId, null);
    await _set(kActiveLightName, null);
    await _set(kTodayCount, 0);
    await _set(kLastRecordedMs, null);
    await _requestWidgetRedraw();
  }

  /// Merges widget-recorded taps into SQLite. Returns how many new events
  /// were inserted (duplicates and events for deleted lights are dropped).
  static Future<int> mergePendingEvents(LightRepository repo) async {
    final raw = await _get<String>(kPendingEvents);
    if (raw == null || raw.isEmpty || raw == '[]') return 0;
    // Clear before inserting: a tap landing in this millisecond-wide window is
    // an accepted micro-race; the UNIQUE(light_id, ts_ms) index means replays
    // can never duplicate.
    await _set(kPendingEvents, '[]');

    List<dynamic> parsed;
    try {
      parsed = jsonDecode(raw) as List<dynamic>;
    } catch (_) {
      return 0;
    }

    final knownLights = (await repo.getLights()).map((l) => l.id).toSet();
    var inserted = 0;
    for (final entry in parsed) {
      if (entry is! Map) continue;
      final lightId = int.tryParse('${entry['lightId']}');
      final ts = entry['ts'];
      if (lightId == null || ts is! num || !knownLights.contains(lightId)) {
        continue;
      }
      if (await repo.recordEvent(lightId, ts.toInt(), 'widget')) inserted++;
    }
    return inserted;
  }

  /// Recomputes the display keys the widget shows (from SQLite, the source of
  /// truth) and asks the OS to redraw the widget.
  static Future<void> pushWidgetState(LightRepository repo) async {
    final id = await getActiveLightId();
    final light = id == null ? null : await repo.getLight(id);
    if (light == null) {
      await clearActiveLight();
      return;
    }
    await _set(kActiveLightName, light.name);
    await _set(kTodayCount, await repo.todayCount(light.id));
    await _set(kCountDate, formatYmd(DateTime.now()));
    await _set(kLastRecordedMs, await repo.lastEventTs(light.id));
    await _requestWidgetRedraw();
  }

  static Future<void> _requestWidgetRedraw() async {
    try {
      await HomeWidget.updateWidget(
        iOSName: iosWidgetName,
        androidName: androidWidgetName,
      );
    } catch (_) {}
  }

  static String formatYmd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
