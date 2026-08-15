import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  static const dbFileName = 'greenlight.db';

  /// Opens the app database. Tests pass `databaseFactoryFfi` and
  /// `inMemoryDatabasePath` to run against sqlite3 on the host.
  static Future<Database> open({DatabaseFactory? factory, String? path}) async {
    final f = factory ?? databaseFactory;
    final resolvedPath = path ?? p.join(await f.getDatabasesPath(), dbFileName);
    return f.openDatabase(
      resolvedPath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: createSchema,
      ),
    );
  }

  static Future<void> createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE lights (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        lat REAL NOT NULL,
        lng REAL NOT NULL,
        created_at INTEGER NOT NULL
      )''');
    // UNIQUE(light_id, ts_ms) makes pending-queue merges idempotent: replaying
    // the same widget tap can never create a duplicate event.
    await db.execute('''
      CREATE TABLE events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        light_id INTEGER NOT NULL REFERENCES lights(id) ON DELETE CASCADE,
        ts_ms INTEGER NOT NULL,
        source TEXT NOT NULL CHECK (source IN ('app','widget')),
        created_at INTEGER NOT NULL,
        UNIQUE(light_id, ts_ms) ON CONFLICT IGNORE
      )''');
    await db.execute('CREATE INDEX idx_events_light_ts ON events(light_id, ts_ms)');
  }
}
