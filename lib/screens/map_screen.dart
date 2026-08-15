import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../app_state.dart';
import '../constants.dart';
import '../data/light_repository.dart';
import 'light_detail_screen.dart';

class MapScreen extends StatefulWidget {
  final AppState state;

  const MapScreen({super.key, required this.state});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _map = MapController();

  static const _fallbackCenter = LatLng(50.8466, 4.3528); // Brussels

  @override
  void initState() {
    super.initState();
    // Only jump to the user when no light is selected yet; otherwise the last
    // used light is the more useful anchor.
    if (widget.state.activeLight == null) _centerOnUser(silent: true);
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
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New traffic light'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Name',
            hintText: 'e.g. Home → office, crossing at bakery',
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
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
    );
    if (name == null || name.trim().isEmpty) return;
    final light =
        await widget.state.addLight(name.trim(), at.latitude, at.longitude);
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
              leading: const Icon(Icons.traffic, color: Colors.green),
              title: Text(light.name,
                  style: Theme.of(ctx).textTheme.titleLarge),
              subtitle: Text(
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
                  initialZoom: active == null ? 12 : 16,
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
                        Marker(
                          point: LatLng(light.lat, light.lng),
                          width: 44,
                          height: 44,
                          child: GestureDetector(
                            onTap: () => _onMarkerTap(light),
                            child: _LightPin(
                              active: light.id == active?.id,
                              count: widget.state.eventCounts[light.id] ?? 0,
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

class _LightPin extends StatelessWidget {
  final bool active;
  final int count;

  const _LightPin({required this.active, required this.count});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: active ? Colors.green : Colors.blueGrey,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [
              BoxShadow(blurRadius: 4, color: Colors.black38),
            ],
          ),
          child: const Icon(Icons.traffic, color: Colors.white, size: 24),
        ),
        if (count > 0)
          Positioned(
            right: -4,
            top: -4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.black26),
              ),
              child: Text('$count',
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ),
      ],
    );
  }
}
