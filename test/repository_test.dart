import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:greenlight/data/db.dart';
import 'package:greenlight/data/defaults.dart';
import 'package:greenlight/data/light_repository.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late LightRepository repo;

  setUp(() async {
    final db = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    repo = LightRepository(db);
  });

  tearDown(() => repo.db.close());

  test('create light, record events, read them back in order', () async {
    final light = await repo.createLight('Dam square', 52.373, 4.893);
    expect(await repo.recordEvent(light.id, 1000, 'app'), isTrue);
    expect(await repo.recordEvent(light.id, 3000, 'widget'), isTrue);
    expect(await repo.recordEvent(light.id, 2000, 'app'), isTrue);

    expect(await repo.eventTimestamps(light.id), [1000, 2000, 3000]);
    final events = await repo.eventsForLight(light.id);
    expect(events.map((e) => e.tsMs), [3000, 2000, 1000]);
    expect(await repo.totalCount(light.id), 3);
    expect(await repo.lastEventTs(light.id), 3000);
  });

  test('duplicate (light_id, ts_ms) insert is ignored, not an error', () async {
    final light = await repo.createLight('A', 0, 0);
    expect(await repo.recordEvent(light.id, 5000, 'app'), isTrue);
    expect(await repo.recordEvent(light.id, 5000, 'widget'), isFalse);
    expect(await repo.totalCount(light.id), 1);

    final other = await repo.createLight('B', 1, 1);
    expect(await repo.recordEvent(other.id, 5000, 'app'), isTrue,
        reason: 'same ts on a different light is a distinct event');
  });

  test('deleting a light cascades its events', () async {
    final light = await repo.createLight('A', 0, 0);
    await repo.recordEvent(light.id, 1, 'app');
    await repo.recordEvent(light.id, 2, 'app');
    await repo.deleteLight(light.id);
    expect(await repo.getLight(light.id), isNull);
    final counts = await repo.eventCountsByLight();
    expect(counts, isEmpty);
  });

  test('todayCount counts only events since local midnight', () async {
    final light = await repo.createLight('A', 0, 0);
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day);
    await repo.recordEvent(
        light.id, midnight.millisecondsSinceEpoch - 1000, 'app');
    await repo.recordEvent(
        light.id, midnight.millisecondsSinceEpoch + 1000, 'app');
    await repo.recordEvent(light.id, now.millisecondsSinceEpoch, 'app');
    expect(await repo.todayCount(light.id), 2);
  });

  test('csv and json export include all events', () async {
    final light = await repo.createLight('Say "go"', 52.0, 4.0);
    await repo.recordEvent(light.id, 1700000000000, 'app');
    await repo.recordEvent(light.id, 1700000090000, 'widget');
    final events = await repo.eventsForLight(light.id);

    final csv = repo.eventsToCsv(light, events);
    final lines = csv.trim().split('\n');
    expect(lines.length, 3, reason: 'header + 2 events');
    expect(lines.first,
        'event_id,light_id,light_name,light_type,ts_ms,iso8601_local,source');
    expect(csv, contains('"Say ""go"""'), reason: 'quotes escaped');
    expect(csv, contains('1700000090000'));

    final json = repo.eventsToJson(light, events);
    expect(json, contains('"ts_ms": 1700000000000'));
    expect(json, contains('"source": "widget"'));
    expect(json, contains('"type": "pedestrian"'));
  });

  test('light type round-trips and defaults to pedestrian', () async {
    final walk = await repo.createLight('W', 0, 0);
    final bike = await repo.createLight('B', 0, 1, type: LightType.bike);
    final car = await repo.createLight('C', 0, 2, type: LightType.car);
    final byId = {for (final l in await repo.getLights()) l.id: l.type};
    expect(byId[walk.id], LightType.pedestrian);
    expect(byId[bike.id], LightType.bike);
    expect(byId[car.id], LightType.car);
  });

  test('green duration round-trips; unset falls back to the default', () async {
    final light = await repo.createLight('A', 0, 0);
    expect(light.greenS, isNull);
    expect(light.effectiveGreenS, Light.defaultGreenS);

    await repo.setGreenSeconds(light.id, 25);
    expect((await repo.getLight(light.id))!.greenS, 25);
    expect((await repo.getLight(light.id))!.effectiveGreenS, 25);

    await repo.setGreenSeconds(light.id, null);
    expect((await repo.getLight(light.id))!.greenS, isNull);
  });

  test('v2 database migrates to v3, green duration starts unset', () async {
    final dir = await Directory.systemTemp.createTemp('greenlight_mig_v2');
    final path = p.join(dir.path, 'mig2.db');
    final v2 = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE lights (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              lat REAL NOT NULL, lng REAL NOT NULL,
              type TEXT NOT NULL DEFAULT 'pedestrian',
              created_at INTEGER NOT NULL
            )''');
        },
      ),
    );
    await v2.insert(
        'lights', {'name': 'Old', 'lat': 1.0, 'lng': 2.0, 'created_at': 3});
    await v2.close();

    final v3 = await AppDatabase.open(factory: databaseFactoryFfi, path: path);
    final lights = await LightRepository(v3).getLights();
    expect(lights.single.greenS, isNull);
    expect(lights.single.effectiveGreenS, Light.defaultGreenS);
    await v3.close();
    await dir.delete(recursive: true);
  });

  test('v1 database migrates to v2, existing lights become pedestrian',
      () async {
    final dir = await Directory.systemTemp.createTemp('greenlight_migration');
    final path = p.join(dir.path, 'mig.db');
    final v1 = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE lights (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              lat REAL NOT NULL, lng REAL NOT NULL,
              created_at INTEGER NOT NULL
            )''');
          await db.execute('''
            CREATE TABLE events (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              light_id INTEGER NOT NULL REFERENCES lights(id) ON DELETE CASCADE,
              ts_ms INTEGER NOT NULL,
              source TEXT NOT NULL CHECK (source IN ('app','widget')),
              created_at INTEGER NOT NULL,
              UNIQUE(light_id, ts_ms) ON CONFLICT IGNORE
            )''');
        },
      ),
    );
    await v1.insert('lights',
        {'name': 'Old', 'lat': 1.0, 'lng': 2.0, 'created_at': 3});
    await v1.close();

    final v2 = await AppDatabase.open(factory: databaseFactoryFfi, path: path);
    final migrated = LightRepository(v2);
    final lights = await migrated.getLights();
    expect(lights.single.name, 'Old');
    expect(lights.single.type, LightType.pedestrian);
    await v2.close();
    await dir.delete(recursive: true);
  });

  test('seeding inserts the 4 Naamsepoort pedestrian crossings', () async {
    await seedNaamsepoortDefaults(repo);
    final lights = await repo.getLights();
    expect(lights.length, 4);
    expect(lights.every((l) => l.type == LightType.pedestrian), isTrue);
    expect(lights.every((l) => l.name.startsWith('Naamsepoort')), isTrue);
  });

  test('onFreshInstall fires on creation, not on reopen', () async {
    final dir = await Directory.systemTemp.createTemp('greenlight_fresh');
    final path = p.join(dir.path, 'fresh.db');
    var calls = 0;
    final db1 = await AppDatabase.open(
        factory: databaseFactoryFfi, path: path, onFreshInstall: () => calls++);
    await db1.close();
    expect(calls, 1);
    final db2 = await AppDatabase.open(
        factory: databaseFactoryFfi, path: path, onFreshInstall: () => calls++);
    await db2.close();
    expect(calls, 1, reason: 'existing DB must not re-trigger seeding');
    await dir.delete(recursive: true);
  });
}
