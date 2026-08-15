import 'light_repository.dart';

/// Starter pins: the four signal-controlled pedestrian crossings at
/// Naamsepoort, Leuven. Coordinates are midpoints of the zebra-marked
/// `crossing=traffic_signals` nodes in OpenStreetMap (queried Aug 2026).
/// Each crossing has a signal head per direction (8 in total), but paired
/// heads turn green together — one pin per crossing.
const _naamsepoortCrossings = [
  ('Naamsepoort — ring west', 50.86864, 4.69830),
  ('Naamsepoort — ring east', 50.86863, 4.69877),
  ('Naamsepoort — Naamsestraat (city side)', 50.86884, 4.69855),
  ('Naamsepoort — Naamsestraat (south side)', 50.86851, 4.69839),
];

/// Called exactly once per install, right after the database file is created
/// (see AppDatabase.open's onFreshInstall). Deleting these later never
/// resurrects them — creation only ever happens once per DB file.
Future<void> seedNaamsepoortDefaults(LightRepository repo) async {
  for (final (name, lat, lng) in _naamsepoortCrossings) {
    await repo.createLight(name, lat, lng, type: LightType.pedestrian);
  }
}
