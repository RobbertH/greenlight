import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../app_state.dart';
import '../constants.dart';
import '../data/light_repository.dart';
import '../prediction/cycle_estimator.dart';
import '../util.dart';
import 'light_detail_screen.dart';
import 'widgets/light_type_ui.dart';

class MapScreen extends StatefulWidget {
  final AppState state;

  const MapScreen({super.key, required this.state});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _map = MapController();

  // Default focus: Naamsepoort, Leuven. No auto-jump to the user's location —
  // the locate button is there when needed.
  static const _fallbackCenter = LatLng(defaultCenterLat, defaultCenterLng);

  LightType _newLightType = LightType.pedestrian;
  final Set<LightType> _shownTypes = {...LightType.values};
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Ticks the pin countdowns once a second. Cheap: pins re-render from the
    // cached estimates in AppState; no estimator work happens here.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final anyUsable = widget.state.estimates.values
          .any((e) => e != null && e.tier != ConfidenceTier.insufficient);
      if (anyUsable) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _centerOnUser({bool silent = false}) async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (!silent) _snack('Location permission denied');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      if (mounted) _map.move(LatLng(pos.latitude, pos.longitude), 16);
    } catch (_) {
      if (!silent) _snack('Could not determine your location');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _addLightDialog(LatLng at) async {
    final controller = TextEditingController(
        text: 'Light ${widget.state.lights.length + 1}');
    var type = _newLightType;
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('New traffic light'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'e.g. Home → office, crossing at bakery',
                ),
                onSubmitted: (v) => Navigator.of(ctx).pop(v),
              ),
              const SizedBox(height: 16),
              SegmentedButton<LightType>(
                segments: [
                  for (final t in LightType.values)
                    ButtonSegment(
                      value: t,
                      icon: Icon(t.icon),
                      tooltip: t.label,
                    ),
                ],
                selected: {type},
                onSelectionChanged: (s) =>
                    setDialogState(() => type = s.first),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.of(ctx).pop(controller.text),
                child: const Text('Add')),
          ],
        ),
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    _newLightType = type; // remember for the next dialog
    // A filtered-out type would make the new pin invisible — the add would
    // look like it failed. Force its chip on.
    setState(() => _shownTypes.add(type));
    final light = await widget.state
        .addLight(name.trim(), at.latitude, at.longitude, type: type);
    await widget.state.selectLight(light);
    _snack('“${light.name}” added and selected');
  }

  Future<void> _onMarkerTap(Light light) async {
    await widget.state.selectLight(light);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(light.type.icon, color: Colors.green),
              title: Text(light.name,
                  style: Theme.of(ctx).textTheme.titleLarge),
              subtitle: Text(
                  '${light.type.label} light · '
                  '${widget.state.eventCounts[light.id] ?? 0} greens recorded · '
                  'now active (the widget records this light)'),
            ),
            ListTile(
              leading: const Icon(Icons.radio_button_checked),
              title: const Text('Record now'),
              onTap: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).pushNamed(kRecordRoute);
              },
            ),
            ListTile(
              leading: const Icon(Icons.insights),
              title: const Text('Details & history'),
              onTap: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) =>
                      LightDetailScreen(state: widget.state, light: light),
                ));
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: ListenableBuilder(
          listenable: widget.state,
          builder: (_, child) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Greenlight'),
              Text(
                widget.state.activeLight == null
                    ? 'No light selected'
                    : 'Active: ${widget.state.activeLight!.name}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location),
            tooltip: 'Center on my location',
            onPressed: _centerOnUser,
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: widget.state,
        builder: (context, _) {
          final active = widget.state.activeLight;
          return Stack(
            children: [
              FlutterMap(
                mapController: _map,
                options: MapOptions(
                  initialCenter: active == null
                      ? _fallbackCenter
                      : LatLng(active.lat, active.lng),
                  initialZoom: active == null ? defaultZoom : 17,
                  onLongPress: (_, latLng) => _addLightDialog(latLng),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.robberthofman.greenlight',
                  ),
                  MarkerLayer(
                    markers: [
                      for (final light in widget.state.lights)
                        if (_shownTypes.contains(light.type))
                          Marker(
                            point: LatLng(light.lat, light.lng),
                            width: 56,
                            height: 80,
                            child: GestureDetector(
                              onTap: () => _onMarkerTap(light),
                              child: _LightPin(
                                active: light.id == active?.id,
                                type: light.type,
                                count: widget.state.eventCounts[light.id] ?? 0,
                                estimate: widget.state.estimates[light.id],
                                greenSeconds: light.effectiveGreenS,
                              ),
                            ),
                          ),
                    ],
                  ),
                  const RichAttributionWidget(
                    attributions: [
                      TextSourceAttribution('© OpenStreetMap contributors'),
                    ],
                  ),
                ],
              ),
              Positioned(
                top: 8,
                left: 8,
                right: 8,
                child: Wrap(
                  spacing: 6,
                  children: [
                    for (final t in LightType.values)
                      FilterChip(
                        avatar: Icon(t.icon, size: 18),
                        label: Text(t.label),
                        showCheckmark: false,
                        selected: _shownTypes.contains(t),
                        onSelected: (on) => setState(() {
                          on ? _shownTypes.add(t) : _shownTypes.remove(t);
                        }),
                      ),
                  ],
                ),
              ),
              if (widget.state.lights.isEmpty)
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: 96,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Long-press the map where a traffic light is to start '
                        'tracking it.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: ListenableBuilder(
        listenable: widget.state,
        builder: (context, _) => FloatingActionButton.extended(
          heroTag: 'record',
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.traffic),
          label: Text(widget.state.activeLight == null
              ? 'Select a light first'
              : 'Record ${widget.state.activeLight!.name}'),
          onPressed: () {
            if (widget.state.activeLight == null) {
              _snack(widget.state.lights.isEmpty
                  ? 'Long-press the map to add a traffic light first'
                  : 'Tap a pin to select the light you are waiting at');
            } else {
              Navigator.of(context).pushNamed(kRecordRoute);
            }
          },
        ),
      ),
    );
  }
}

/// Map pin: record count on top, the type icon in a circle colored by the
/// light's predicted state (green/red once a confident fit exists, grey
/// before), and the live next-green countdown underneath.
class _LightPin extends StatelessWidget {
  final bool active;
  final LightType type;
  final int count;
  final CycleEstimate? estimate;
  final int greenSeconds;

  const _LightPin({
    required this.active,
    required this.type,
    required this.count,
    required this.estimate,
    required this.greenSeconds,
  });

  @override
  Widget build(BuildContext context) {
    final est = estimate;
    final usable = est != null && est.tier != ConfidenceTier.insufficient;
    final now = DateTime.now().millisecondsSinceEpoch;
    final green = usable && est.isGreenAt(now, greenSeconds);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _pill('$count', Colors.black87),
        const SizedBox(height: 2),
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: !usable
                ? Colors.blueGrey
                : green
                    ? Colors.green
                    : Colors.red.shade600,
            shape: BoxShape.circle,
            // The active light (the one the record button and home-screen
            // widget target) gets an amber ring instead of a white one.
            border: Border.all(
                color: active ? Colors.amber : Colors.white,
                width: active ? 3 : 2),
            boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black38)],
          ),
          child: Icon(type.icon, color: Colors.white, size: 22),
        ),
        if (usable) ...[
          const SizedBox(height: 2),
          _pill(
            green ? 'green' : fmtCountdown(est.nextGreenMs(now) - now),
            green ? Colors.green.shade800 : Colors.red.shade800,
          ),
        ],
      ],
    );
  }

  Widget _pill(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.black26),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.bold, color: color)),
      );
}
