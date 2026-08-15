import 'package:flutter_test/flutter_test.dart';
import 'package:greenlight/data/db.dart';
import 'package:greenlight/data/light_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
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
        'event_id,light_id,light_name,ts_ms,iso8601_local,source');
    expect(csv, contains('"Say ""go"""'), reason: 'quotes escaped');
    expect(csv, contains('1700000090000'));

    final json = repo.eventsToJson(light, events);
    expect(json, contains('"ts_ms": 1700000000000'));
    expect(json, contains('"source": "widget"'));
  });
}
