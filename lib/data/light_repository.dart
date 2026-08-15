import 'dart:convert';

import 'package:sqflite/sqflite.dart';

/// What kind of signal this light controls. Pedestrian and bike crossings
/// usually have one signal head per direction, but paired heads of the same
/// crossing turn green together — so one Light represents the whole crossing.
enum LightType {
  pedestrian('pedestrian', 'Pedestrian'),
  bike('bike', 'Bike'),
  car('car', 'Car');

  final String dbValue;
  final String label;

  const LightType(this.dbValue, this.label);

  static LightType fromDb(String? v) => LightType.values
      .firstWhere((t) => t.dbValue == v, orElse: () => LightType.pedestrian);
}

class Light {
  /// Assumed green window when the user has not configured one for a light.
  static const defaultGreenS = 10;

  final int id;
  final String name;
  final double lat;
  final double lng;
  final LightType type;

  /// How long this light stays green after an onset, in seconds.
  /// Null until the user sets it in the light's settings.
  final int? greenS;
  final int createdAt;

  const Light({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    required this.type,
    this.greenS,
    required this.createdAt,
  });

  int get effectiveGreenS => greenS ?? defaultGreenS;

  factory Light.fromRow(Map<String, Object?> row) => Light(
        id: row['id'] as int,
        name: row['name'] as String,
        lat: (row['lat'] as num).toDouble(),
        lng: (row['lng'] as num).toDouble(),
        type: LightType.fromDb(row['type'] as String?),
        greenS: row['green_s'] as int?,
        createdAt: row['created_at'] as int,
      );
}

class LightEvent {
  final int id;
  final int lightId;
  final int tsMs;
  final String source;
  final int createdAt;

  const LightEvent({
    required this.id,
    required this.lightId,
    required this.tsMs,
    required this.source,
    required this.createdAt,
  });

  factory LightEvent.fromRow(Map<String, Object?> row) => LightEvent(
        id: row['id'] as int,
        lightId: row['light_id'] as int,
        tsMs: row['ts_ms'] as int,
        source: row['source'] as String,
        createdAt: row['created_at'] as int,
      );
}

class LightRepository {
  final Database db;

  LightRepository(this.db);

  Future<List<Light>> getLights() async =>
      (await db.query('lights', orderBy: 'created_at')).map(Light.fromRow).toList();

  Future<Light?> getLight(int id) async {
    final rows = await db.query('lights', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Light.fromRow(rows.first);
  }

  Future<Light> createLight(String name, double lat, double lng,
      {LightType type = LightType.pedestrian}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = await db.insert('lights', {
      'name': name,
      'lat': lat,
      'lng': lng,
      'type': type.dbValue,
      'created_at': now,
    });
    return Light(
        id: id, name: name, lat: lat, lng: lng, type: type, createdAt: now);
  }

  Future<void> renameLight(int id, String name) =>
      db.update('lights', {'name': name}, where: 'id = ?', whereArgs: [id]);

  Future<void> setGreenSeconds(int id, int? seconds) =>
      db.update('lights', {'green_s': seconds},
          where: 'id = ?', whereArgs: [id]);

  Future<void> deleteLight(int id) async {
    await db.delete('lights', where: 'id = ?', whereArgs: [id]);
  }

  /// Inserts a green-transition event. Returns false when an identical
  /// (light_id, ts_ms) event already existed (the DDL-level ON CONFLICT IGNORE
  /// swallows the insert, so the reliable signal is `changes()`).
  Future<bool> recordEvent(int lightId, int tsMs, String source) async {
    await db.insert('events', {
      'light_id': lightId,
      'ts_ms': tsMs,
      'source': source,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    final changed = Sqflite.firstIntValue(await db.rawQuery('SELECT changes()')) ?? 0;
    return changed > 0;
  }

  Future<List<LightEvent>> eventsForLight(int lightId, {int? limit}) async =>
      (await db.query(
        'events',
        where: 'light_id = ?',
        whereArgs: [lightId],
        orderBy: 'ts_ms DESC',
        limit: limit,
      ))
          .map(LightEvent.fromRow)
          .toList();

  /// Ascending epoch-ms timestamps, the input shape the cycle estimator wants.
  Future<List<int>> eventTimestamps(int lightId) async =>
      (await db.query('events',
              columns: ['ts_ms'],
              where: 'light_id = ?',
              whereArgs: [lightId],
              orderBy: 'ts_ms ASC'))
          .map((r) => r['ts_ms'] as int)
          .toList();

  Future<void> deleteEvent(int id) async {
    await db.delete('events', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> totalCount(int lightId) async =>
      Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM events WHERE light_id = ?', [lightId])) ??
      0;

  /// Events since local midnight.
  Future<int> todayCount(int lightId) async {
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    return Sqflite.firstIntValue(await db.rawQuery(
            'SELECT COUNT(*) FROM events WHERE light_id = ? AND ts_ms >= ?',
            [lightId, midnight])) ??
        0;
  }

  Future<int?> lastEventTs(int lightId) async => Sqflite.firstIntValue(await db
      .rawQuery('SELECT MAX(ts_ms) FROM events WHERE light_id = ?', [lightId]));

  Future<Map<int, int>> eventCountsByLight() async {
    final rows = await db
        .rawQuery('SELECT light_id, COUNT(*) AS n FROM events GROUP BY light_id');
    return {for (final r in rows) r['light_id'] as int: r['n'] as int};
  }

  String eventsToCsv(Light light, List<LightEvent> events) {
    final name = '"${light.name.replaceAll('"', '""')}"';
    final b = StringBuffer(
        'event_id,light_id,light_name,light_type,ts_ms,iso8601_local,source\n');
    for (final e in events) {
      final iso = DateTime.fromMillisecondsSinceEpoch(e.tsMs).toIso8601String();
      b.writeln(
          '${e.id},${e.lightId},$name,${light.type.dbValue},${e.tsMs},$iso,${e.source}');
    }
    return b.toString();
  }

  String eventsToJson(Light light, List<LightEvent> events) =>
      const JsonEncoder.withIndent('  ').convert({
        'light': {
          'id': light.id,
          'name': light.name,
          'lat': light.lat,
          'lng': light.lng,
          'type': light.type.dbValue,
        },
        'events': [
          for (final e in events)
            {
              'ts_ms': e.tsMs,
              'iso_local':
                  DateTime.fromMillisecondsSinceEpoch(e.tsMs).toIso8601String(),
              'source': e.source,
            }
        ],
      });
}
