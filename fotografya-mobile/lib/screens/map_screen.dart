import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../core/config.dart';
import '../core/l10n.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../state/providers.dart';
import '../widgets/common.dart';

const _specialties = [
  'astro',
  'landscape',
  'street',
  'portrait',
  'wildlife',
  'sports',
  'architecture',
  'documentary',
  'wedding',
  'macro',
  'aerial',
  'travel',
];

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key, this.initial, this.photos = false});
  final LatLng? initial;
  final bool photos;

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final _map = MapController();
  late bool _photos = widget.photos;
  String _specialty = '';
  ({String bbox, int zoom})? _view;
  Timer? _debounce;
  Object? _selected; // MapPhotographer | MapPhotoPoint

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onMove(MapCamera camera) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      final b = camera.visibleBounds;
      double wrap(double x) => ((x + 180) % 360 + 360) % 360 - 180;
      final full = b.east - b.west >= 360;
      final bbox = [
        full ? -180.0 : wrap(b.west),
        math.max(-90.0, b.south),
        full ? 180.0 : wrap(b.east),
        math.min(90.0, b.north),
      ].map((n) => n.toStringAsFixed(4)).join(',');
      if (mounted)
        setState(() => _view = (bbox: bbox, zoom: camera.zoom.round()));
    });
  }

  void _zoomInto(MapCluster c) =>
      _map.move(LatLng(c.lat, c.lng), math.min(_map.camera.zoom + 2, 16));

  Widget _cluster(MapCluster c, Palette p) {
    final size = math.min(64.0, 30 + math.log(c.count) / math.ln2 * 7);
    if (c.thumbUrl != null) {
      return GestureDetector(
        onTap: () => _zoomInto(c),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [BoxShadow(blurRadius: 12, color: Colors.black38)],
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              NetPhoto(url: c.thumbUrl!),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  color: Colors.black87,
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: Text(
                    '${c.count}',
                    style: font(11, weight: 600, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return GestureDetector(
      onTap: () => _zoomInto(c),
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: p.ink,
          shape: BoxShape.circle,
          border: Border.all(color: p.ink.withValues(alpha: 0.2), width: 4),
        ),
        child: Text('${c.count}', style: font(13, weight: 600, color: p.mat)),
      ),
    );
  }

  List<Marker> _markers(Palette p) {
    final v = _view;
    if (v == null) return const [];
    if (_photos) {
      final d = ref.watch(photoMapProvider((v.bbox, v.zoom))).asData?.value;
      if (d == null) return const [];
      return [
        for (final c in d.clusters)
          Marker(
            point: LatLng(c.lat, c.lng),
            width: 66,
            height: 66,
            child: _cluster(c, p),
          ),
        for (final ph in d.items)
          Marker(
            point: LatLng(ph.lat, ph.lng),
            width: 56,
            height: 56,
            child: GestureDetector(
              onTap: () => setState(() => _selected = ph),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: identical(_selected, ph) ? p.accent : Colors.white,
                    width: 3,
                  ),
                  boxShadow: const [
                    BoxShadow(blurRadius: 12, color: Colors.black38),
                  ],
                ),
                child: ph.thumbUrl == null
                    ? const SizedBox()
                    : NetPhoto(url: ph.thumbUrl!),
              ),
            ),
          ),
      ];
    }
    final d = ref
        .watch(photographerMapProvider((v.bbox, v.zoom, _specialty)))
        .asData
        ?.value;
    if (d == null) return const [];
    return [
      for (final c in d.clusters)
        Marker(
          point: LatLng(c.lat, c.lng),
          width: 64,
          height: 64,
          child: _cluster(c, p),
        ),
      for (final u in d.items)
        Marker(
          point: LatLng(u.lat, u.lng),
          width: 46,
          height: 46,
          child: GestureDetector(
            onTap: () => setState(() => _selected = u),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: identical(_selected, u) ? p.accent : Colors.white,
                  width: 3,
                ),
                boxShadow: const [
                  BoxShadow(blurRadius: 12, color: Colors.black38),
                ],
              ),
              child: Avatar(
                name: u.user.displayName,
                url: u.user.avatarUrl,
                size: 40,
              ),
            ),
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    final me = ref.watch(authProvider).asData?.value;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final start =
        widget.initial ??
        (me?.latitude != null && me?.longitude != null
            ? LatLng(me!.latitude!, me.longitude!)
            : const LatLng(39.2, 35.2));
    final v = _view;
    final total = v == null
        ? null
        : _photos
        ? ref.watch(photoMapProvider((v.bbox, v.zoom))).asData?.value.total
        : ref
              .watch(photographerMapProvider((v.bbox, v.zoom, _specialty)))
              .asData
              ?.value
              .total;

    return Scaffold(
      appBar: AppBar(title: Text(t('map.title'))),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: start,
              initialZoom: widget.initial != null
                  ? 12
                  : (me?.latitude != null ? 7 : 5),
              onMapReady: () => _onMove(_map.camera),
              onPositionChanged: (camera, _) => _onMove(camera),
              onTap: (_, _) => setState(() => _selected = null),
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: dark
                    ? AppConfig.mapTilesDark
                    : AppConfig.mapTilesLight,
                subdomains: const ['a', 'b', 'c', 'd'],
                retinaMode: RetinaMode.isHighDensity(context),
                userAgentPackageName: 'app.fotografya.fotografya',
              ),
              MarkerLayer(markers: _markers(p)),
              const RichAttributionWidget(
                attributions: [TextSourceAttribution(AppConfig.mapAttribution)],
              ),
            ],
          ),
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Material(
                  color: p.mat,
                  shape: const StadiumBorder(),
                  elevation: 3,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: SegmentedButton<bool>(
                      segments: [
                        ButtonSegment(
                          value: false,
                          label: Text(t('map.photographers')),
                        ),
                        ButtonSegment(
                          value: true,
                          label: Text(t('map.photos')),
                        ),
                      ],
                      selected: {_photos},
                      showSelectedIcon: false,
                      onSelectionChanged: (s) => setState(() {
                        _photos = s.first;
                        _selected = null;
                      }),
                    ),
                  ),
                ),
                if (!_photos) ...[
                  const SizedBox(height: 8),
                  Material(
                    color: p.mat,
                    shape: const StadiumBorder(),
                    elevation: 3,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: DropdownButton<String>(
                        value: _specialty,
                        underline: const SizedBox.shrink(),
                        style: font(14, color: p.ink),
                        items: [
                          DropdownMenuItem(
                            value: '',
                            child: Text(t('map.all_specialties')),
                          ),
                          for (final s in _specialties)
                            DropdownMenuItem(
                              value: s,
                              child: Text(t('specialties.$s')),
                            ),
                        ],
                        onChanged: (v) => setState(() => _specialty = v ?? ''),
                      ),
                    ),
                  ),
                ],
                if (total != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: ShapeDecoration(
                      color: p.mat.withValues(alpha: 0.92),
                      shape: const StadiumBorder(),
                    ),
                    child: Text(
                      t(
                        _photos
                            ? 'map.count_photos'
                            : 'map.count_photographers',
                        {'count': total},
                      ),
                      style: font(12, color: p.muted),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (_selected != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 12 + MediaQuery.paddingOf(context).bottom,
              child: _card(context, me?.id),
            ),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, String? meId) {
    final t = L10n.of(context);
    final p = context.palette;
    final s = _selected;
    return Material(
      color: p.mat,
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: switch (s) {
          MapPhotographer u => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Avatar(
                    name: u.user.displayName,
                    url: u.user.avatarUrl,
                    size: 50,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          u.user.displayName,
                          style: font(16, weight: 600, color: p.ink),
                        ),
                        Text(
                          u.city ?? t('map.approximate'),
                          style: font(13.5, color: p.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (u.specialties.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final x in u.specialties.take(5))
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: ShapeDecoration(
                          color: p.ink.withValues(alpha: 0.06),
                          shape: const StadiumBorder(),
                        ),
                        child: Text(
                          t('specialties.$x'),
                          style: font(12.5, color: p.ink),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => context.push('/u/${u.user.username}'),
                      child: Text(t('map.profile')),
                    ),
                  ),
                  if (meId != u.user.id) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: () =>
                            context.push('/messages/new/${u.user.username}'),
                        child: Text(t('map.message')),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Text(t('map.privacy_note'), style: font(11.5, color: p.muted)),
            ],
          ),
          MapPhotoPoint ph => InkWell(
            onTap: () => context.push('/p/${ph.photoId}'),
            child: Row(
              children: [
                if (ph.thumbUrl != null)
                  SizedBox(
                    width: 84,
                    height: 84,
                    child: NetPhoto(url: ph.thumbUrl!),
                  ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ph.title ?? '',
                        style: font(16, weight: 600, color: p.ink),
                      ),
                      Text(
                        ph.user.displayName,
                        style: font(13.5, color: p.muted),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        t('map.open_photo'),
                        style: font(14, weight: 600, color: p.accent),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _ => const SizedBox.shrink(),
        },
      ),
    );
  }
}
