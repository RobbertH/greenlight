import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  static const dbFileName = 'greenlight.db';

  /// Opens the app database. Tests pass `databaseFactoryFfi` and
  /// `inMemoryDatabasePath` to run against sqlite3 on the host.
  /// [onFreshInstall] fires exactly when the DB file was just created — the
  /// reliable "first run" signal (an upgraded v1 DB never re-runs creation).
  static Future<Database> open({
    DatabaseFactory? factory,
    String? path,
    void Function()? onFreshInstall,
  }) async {
    final f = factory ?? databaseFactory;
    final resolvedPath = path ?? p.join(await f.getDatabasesPath(), dbFileName);
    return f.openDatabase(
      resolvedPath,
      options: OpenDatabaseOptions(
        version: 3,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) async {
          await createSchema(db, version);
          onFreshInstall?.call();
        },
        onUpgrade: upgradeSchema,
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
        type TEXT NOT NULL DEFAULT 'pedestrian'
          CHECK (type IN ('pedestrian','bike','car')),
        green_s INTEGER,
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

  static Future<void> upgradeSchema(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
          "ALTER TABLE lights ADD COLUMN type TEXT NOT NULL DEFAULT 'pedestrian'");
    }
    if (oldVersion < 3) {
      // NULL = not configured; the app falls back to Light.defaultGreenS.
      await db.execute('ALTER TABLE lights ADD COLUMN green_s INTEGER');
    }
  }
}
