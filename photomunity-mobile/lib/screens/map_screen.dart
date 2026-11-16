import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
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
import '../widgets/design.dart';

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
      if (mounted) {
        setState(() => _view = (bbox: bbox, zoom: camera.zoom.round()));
      }
    });
  }

  void _zoomInto(MapCluster c) =>
      _map.move(LatLng(c.lat, c.lng), math.min(_map.camera.zoom + 2, 16));

  Widget _cluster(MapCluster c, Palette p) {
    final size = math.min(64.0, 30 + math.log(c.count) / math.ln2 * 7);
    if (c.thumbUrl != null) {
      return GestureDetector(
        onTap: () => _zoomInto(c),
        child: Stack(
          clipBehavior: Clip.none,
          fit: StackFit.expand,
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: p.surface, width: 3),
                boxShadow: p.shadowFloat,
              ),
              clipBehavior: Clip.antiAlias,
              child: NetPhoto(url: c.thumbUrl!),
            ),
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: ShapeDecoration(color: p.accent, shape: const StadiumBorder()),
                child: Text('${c.count}', style: font(11.5, weight: 700, color: p.accentInk, tabular: true)),
              ),
            ),
          ],
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
          color: p.accent,
          shape: BoxShape.circle,
          border: Border.all(color: p.accent.withValues(alpha: 0.25), width: 5),
        ),
        child: Text('${c.count}', style: font(15, weight: 700, color: p.accentInk, tabular: true)),
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
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: identical(_selected, ph) ? p.accent : p.surface,
                    width: 3,
                  ),
                  boxShadow: p.shadowFloat,
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
                  color: identical(_selected, u) ? p.accent : p.surface,
                  width: 3,
                ),
                boxShadow: p.shadowFloat,
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
                userAgentPackageName: 'app.photomunity.photomunity',
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
            top: MediaQuery.paddingOf(context).top + 8,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (Navigator.of(context).canPop()) ...[
                      DecoratedBox(
                        decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: p.shadowFloat),
                        child: RoundIconButton(
                          icon: LucideIcons.chevronLeft,
                          label: t('ui.back'),
                          color: p.surface,
                          onPressed: () => Navigator.of(context).maybePop(),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    _Segmented(
                      value: _photos,
                      labels: (t('map.photographers'), t('map.photos')),
                      onChanged: (v) => setState(() {
                        _photos = v;
                        _selected = null;
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (!_photos)
                      DecoratedBox(
                        decoration: ShapeDecoration(color: p.surface, shape: const StadiumBorder(), shadows: p.shadowFloat),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: DropdownButton<String>(
                            value: _specialty,
                            underline: const SizedBox.shrink(),
                            borderRadius: BorderRadius.circular(Radii.box),
                            icon: const Icon(LucideIcons.chevronDown, size: 18),
                            style: font(14.5, weight: 600, color: p.ink),
                            items: [
                              DropdownMenuItem(value: '', child: Text(t('map.all_specialties'))),
                              for (final s in _specialties)
                                DropdownMenuItem(value: s, child: Text(t('specialties.$s'))),
                            ],
                            onChanged: (v) => setState(() => _specialty = v ?? ''),
                          ),
                        ),
                      ),
                    if (total != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: ShapeDecoration(color: p.surface, shape: const StadiumBorder(), shadows: p.shadowFloat),
                        child: Text(
                          t(_photos ? 'map.count_photos' : 'map.count_photographers', {'count': total}),
                          style: font(13, weight: 600, color: p.inkMuted, tabular: true),
                        ),
                      ),
                  ],
                ),
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
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(Radii.card),
        boxShadow: p.shadowFloat,
      ),
      child: Padding(
        padding: const EdgeInsets.all(Space.s4),
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
                    size: 52,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          u.user.displayName,
                          style: font(19, weight: 700, spacing: -0.4, color: p.ink),
                        ),
                        Text(
                          [u.city, t('map.approximate')].whereType<String>().join(', '),
                          style: font(14.5, color: p.inkMuted),
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
                    for (final x in u.specialties.take(5)) ExifChip(t('specialties.$x')),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: p.surface2, foregroundColor: p.ink, minimumSize: const Size(0, 48)),
                      onPressed: () => context.push('/u/${u.user.username}'),
                      child: Text(t('map.profile')),
                    ),
                  ),
                  if (meId != u.user.id) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                        onPressed: () =>
                            context.push('/messages/new/${u.user.username}'),
                        icon: const Icon(LucideIcons.messageCircle, size: 20),
                        label: Text(t('map.message')),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Text(t('map.privacy_note'), style: font(11.5, color: p.inkMuted)),
            ],
          ),
          MapPhotoPoint ph => InkWell(
            onTap: () => context.push('/p/${ph.photoId}'),
            child: Row(
              children: [
                if (ph.thumbUrl != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.photo),
                    child: SizedBox(
                      width: 84,
                      height: 84,
                      child: NetPhoto(url: ph.thumbUrl!),
                    ),
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
                        style: font(13.5, color: p.inkMuted),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        t('map.open_photo'),
                        style: font(14, weight: 600, color: p.accentText),
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


/// Hap biçimli iki seçenekli anahtar (Fotoğrafçılar / Fotoğraflar); seçili accent-tint.
class _Segmented extends StatelessWidget {
  const _Segmented({required this.value, required this.labels, required this.onChanged});
  final bool value;
  final (String, String) labels;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget seg(bool v, String label) {
      final on = value == v;
      return Semantics(
        selected: on,
        button: true,
        child: GestureDetector(
          onTap: () => onChanged(v),
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.center,
            decoration: ShapeDecoration(color: on ? p.accentTint : Colors.transparent, shape: const StadiumBorder()),
            child: Text(label, style: font(15.5, weight: 600, color: on ? p.accentText : p.inkMuted)),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: ShapeDecoration(color: p.surface, shape: const StadiumBorder(), shadows: p.shadowFloat),
      child: Row(mainAxisSize: MainAxisSize.min, children: [seg(false, labels.$1), seg(true, labels.$2)]),
    );
  }
}
