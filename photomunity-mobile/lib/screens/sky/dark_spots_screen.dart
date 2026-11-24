import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/config.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/design.dart';
import '../../widgets/intro.dart';
import 'sky_common.dart';

/// NASA GIBS, VIIRS "Black Marble" gece ışıkları (2016 bileşimi). GoogleMapsCompatible_Level8: en çok z8 döşeme;
/// daha yakın zumlarda büyütülerek gösterilir. Işık kirliliği için kaba bir gösterge (Bortle değeri değil).
const _nightLightsUrl =
    'https://gibs.earthdata.nasa.gov/wmts/epsg3857/best/VIIRS_Black_Marble/default/2016-01-01/GoogleMapsCompatible_Level8/{z}/{y}/{x}.png';

/// Karanlık noktalar: harita altlığı üzerinde yarı saydam gece ışıkları katmanı.
class DarkSpotsScreen extends ConsumerStatefulWidget {
  const DarkSpotsScreen({super.key});

  @override
  ConsumerState<DarkSpotsScreen> createState() => _DarkSpotsScreenState();
}

class _DarkSpotsScreenState extends ConsumerState<DarkSpotsScreen> {
  final _map = MapController();
  double _opacity = 0.7;
  LatLng? _picked;

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  String _label(LatLng pt) => '${pt.latitude.toStringAsFixed(3)}, ${pt.longitude.toStringAsFixed(3)}';

  Future<void> _onTap(LatLng pt) async {
    final t = L10n.of(context);
    setState(() => _picked = pt);
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) {
        final p = c.palette;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(LucideIcons.mapPin, size: 20, color: p.accentText),
                    const SizedBox(width: 8),
                    Text(_label(pt), style: font(17, weight: 700, color: p.ink, tabular: true)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(t('dark.point_hint'), style: font(13.5, color: p.inkMuted)),
                const SizedBox(height: 16),
                FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), shape: const StadiumBorder()),
                  icon: const Icon(LucideIcons.calendarPlus, size: 18),
                  label: Text(t('dark.plan_here')),
                  onPressed: () => Navigator.pop(c, 'plan'),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    shape: const StadiumBorder(),
                    backgroundColor: p.surface2,
                    foregroundColor: p.ink,
                  ),
                  icon: const Icon(LucideIcons.locateFixed, size: 18),
                  label: Text(t('dark.set_sky_place')),
                  onPressed: () => Navigator.pop(c, 'place'),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted) return;
    switch (action) {
      case 'plan':
        await context.push(Uri(path: '/sky/plans/new', queryParameters: {
          'kind': 'milkyway',
          'lat': pt.latitude.toStringAsFixed(5),
          'lng': pt.longitude.toStringAsFixed(5),
        }).toString());
      case 'place':
        ref.read(skyPlaceProvider.notifier).set(pt.latitude, pt.longitude, _label(pt));
        toast(context, t('dark.place_set'));
    }
    if (mounted) setState(() => _picked = null);
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    final place = ref.watch(skyPlaceProvider);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final top = MediaQuery.paddingOf(context).top;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final here = LatLng(place.lat, place.lng);
    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: here,
              initialZoom: 7,
              minZoom: 2,
              maxZoom: 12,
              onTap: (_, pt) => _onTap(pt),
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
            ),
            children: [
              TileLayer(
                urlTemplate: dark ? AppConfig.mapTilesDark : AppConfig.mapTilesLight,
                subdomains: const ['a', 'b', 'c', 'd'],
                retinaMode: RetinaMode.isHighDensity(context),
                userAgentPackageName: 'app.photomunity.photomunity',
              ),
              Opacity(
                opacity: _opacity,
                child: TileLayer(
                  urlTemplate: _nightLightsUrl,
                  maxNativeZoom: 8,
                  userAgentPackageName: 'app.photomunity.photomunity',
                ),
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: here,
                    width: 22,
                    height: 22,
                    child: Container(
                      decoration: BoxDecoration(
                        color: p.accent,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: p.shadowFloat,
                      ),
                    ),
                  ),
                  if (_picked != null)
                    Marker(
                      point: _picked!,
                      width: 36,
                      height: 36,
                      alignment: Alignment.topCenter,
                      child: const Icon(LucideIcons.mapPin, size: 34, color: Color(0xFFFFD27A)),
                    ),
                ],
              ),
              Padding(
                padding: EdgeInsets.only(bottom: 150 + bottom),
                child: const RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution('NASA GIBS / VIIRS'),
                    TextSourceAttribution(AppConfig.mapAttribution),
                  ],
                ),
              ),
            ],
          ),
          // Üst çubuk
          Positioned(
            left: 12,
            right: 12,
            top: top + 8,
            child: Row(
              children: [
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
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                    decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(999), boxShadow: p.shadowFloat),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(t('dark.title'), maxLines: 1, overflow: TextOverflow.ellipsis, style: font(16, weight: 700, color: p.ink)),
                        Text(t('dark.tap_hint'), maxLines: 1, overflow: TextOverflow.ellipsis, style: font(12, color: p.inkMuted)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                DecoratedBox(
                  decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: p.shadowFloat),
                  child: const IntroButton(module: 'dark_spots', size: 44),
                ),
              ],
            ),
          ),
          // Konumuma dön
          Positioned(
            right: 12,
            bottom: 200 + bottom,
            child: DecoratedBox(
              decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: p.shadowFloat),
              child: RoundIconButton(
                icon: LucideIcons.locateFixed,
                label: t('dark.center_place'),
                color: p.surface,
                onPressed: () => _map.move(here, _map.camera.zoom),
              ),
            ),
          ),
          // Alt panel: lejant ve saydamlık
          Positioned(
            left: 12,
            right: 12,
            bottom: 12 + bottom,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(24), boxShadow: p.shadowFloat),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 10,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(99),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF05060F), Color(0xFF3A3A55), Color(0xFFFFC36B), Color(0xFFFFF4D6)],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(child: Text(t('dark.legend_dark'), style: font(12, weight: 600, color: p.ink))),
                      Expanded(
                        child: Text(t('dark.legend_bright'), textAlign: TextAlign.right, style: font(12, weight: 600, color: p.ink)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(LucideIcons.layers, size: 16, color: p.inkMuted),
                      const SizedBox(width: 6),
                      Text(t('dark.opacity'), style: font(13, color: p.inkMuted)),
                      Expanded(
                        child: Slider(
                          value: _opacity,
                          min: 0,
                          max: 1,
                          label: '%${(_opacity * 100).round()}',
                          semanticFormatterCallback: (v) => '%${(v * 100).round()}',
                          onChanged: (v) => setState(() => _opacity = v),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
