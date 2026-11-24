import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/config.dart';
import '../core/l10n.dart';
import '../core/theme.dart';

typedef PickedPlace = ({double lat, double lng, String? name});

/// Haritaya dokunarak yer seçtirir (çekim planı, etkinlik). Ad isteğe bağlı.
Future<PickedPlace?> pickPlace(BuildContext context, {double? lat, double? lng, String? name, bool nameRequired = false}) {
  return showModalBottomSheet<PickedPlace>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _PlacePicker(lat: lat, lng: lng, name: name, nameRequired: nameRequired),
  );
}

class _PlacePicker extends StatefulWidget {
  const _PlacePicker({this.lat, this.lng, this.name, required this.nameRequired});
  final double? lat, lng;
  final String? name;
  final bool nameRequired;

  @override
  State<_PlacePicker> createState() => _PlacePickerState();
}

class _PlacePickerState extends State<_PlacePicker> {
  late LatLng? _point = widget.lat != null && widget.lng != null ? LatLng(widget.lat!, widget.lng!) : null;
  late final _name = TextEditingController(text: widget.name);
  final _map = MapController();
  bool _locating = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _locate() async {
    setState(() => _locating = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition();
      final ll = LatLng(pos.latitude, pos.longitude);
      setState(() => _point = ll);
      _map.move(ll, 12);
    } catch (_) {
      // Konum servisi kapalı olabilir
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ok = _point != null && (!widget.nameRequired || _name.text.trim().isNotEmpty);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t('place.title'), style: font(18, weight: 700, color: p.ink)),
            const SizedBox(height: 4),
            Text(t('place.hint'), style: font(13, color: p.inkMuted)),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                height: MediaQuery.sizeOf(context).height * 0.4,
                child: Stack(
                  children: [
                    FlutterMap(
                      mapController: _map,
                      options: MapOptions(
                        initialCenter: _point ?? const LatLng(39.5, 35),
                        initialZoom: _point == null ? 5 : 11,
                        interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                        onTap: (_, ll) => setState(() => _point = ll),
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: dark ? AppConfig.mapTilesDark : AppConfig.mapTilesLight,
                          subdomains: const ['a', 'b', 'c', 'd'],
                          retinaMode: RetinaMode.isHighDensity(context),
                          userAgentPackageName: 'app.photomunity.photomunity',
                        ),
                        if (_point != null)
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: _point!,
                                width: 36,
                                height: 36,
                                alignment: Alignment.topCenter,
                                child: Icon(Icons.location_on, size: 36, color: p.accent),
                              ),
                            ],
                          ),
                      ],
                    ),
                    Positioned(
                      right: 10,
                      top: 10,
                      child: Material(
                        color: p.surface,
                        shape: const StadiumBorder(),
                        child: InkWell(
                          customBorder: const StadiumBorder(),
                          onTap: _locating ? null : _locate,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(LucideIcons.locateFixed, size: 16, color: p.ink),
                                const SizedBox(width: 6),
                                Text(t('planner.my_location'), style: font(13, weight: 600, color: p.ink)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _name,
              maxLength: 200,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: t(widget.nameRequired ? 'place.name' : 'place.name_optional'),
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: ok
                  ? () => Navigator.pop(context, (
                      lat: double.parse(_point!.latitude.toStringAsFixed(5)),
                      lng: double.parse(_point!.longitude.toStringAsFixed(5)),
                      name: _name.text.trim().isEmpty ? null : _name.text.trim(),
                    ))
                  : null,
              child: Text(t('place.use')),
            ),
          ],
        ),
      ),
    );
  }
}
