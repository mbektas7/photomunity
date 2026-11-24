import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/l10n.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../state/providers.dart';
import '../widgets/common.dart';
import '../widgets/design.dart';
import 'feed_screen.dart' show loadMoreOnScroll;

/// Ekipmana göre keşif: bir kamera ya da lensle çekilen kareler, istatistikler, en çok kullanan fotoğrafçılar.
class GearScreen extends ConsumerStatefulWidget {
  const GearScreen({super.key, this.camera, this.lens, this.label});
  final String? camera;
  final String? lens;

  /// Başlıkta gösterilecek ad (ör. marka + model); yoksa sorgu adı.
  final String? label;

  @override
  ConsumerState<GearScreen> createState() => _GearScreenState();
}

class _GearScreenState extends ConsumerState<GearScreen> {
  String _sort = 'recent';

  /// Seçili etiket; null = tümü.
  String? _tag;

  String get _key => Uri(
    path: 'gear/photos',
    queryParameters: {'camera': ?widget.camera, 'lens': ?widget.lens, 'sort': _sort, 'tag': ?_tag},
  ).toString();

  void _photographers(GearStats s) {
    final t = L10n.of(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) {
        final p = c.palette;
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(c).height * 0.6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(t('gear.top_photographers'), style: font(18, weight: 700, color: p.ink)),
                ),
                Expanded(
                  child: ListView(
                    children: [
                      for (final u in s.topPhotographers)
                        ListTile(
                          onTap: () {
                            Navigator.pop(c);
                            context.push('/u/${u.username}');
                          },
                          leading: Avatar(name: u.displayName, url: u.avatarUrl, size: 40),
                          title: Text(u.displayName, style: font(15, weight: 600, color: p.ink)),
                          subtitle: Text('@${u.username}', style: font(13, color: p.inkMuted)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    final locale = t.locale.languageCode;
    final nf = NumberFormat.decimalPattern(locale);
    final isLens = widget.lens != null && widget.camera == null;
    final stats = ref.watch(gearStatsProvider((widget.camera, widget.lens))).asData?.value;
    final pages = ref.watch(cursorPhotosProvider(_key));
    final ctrl = ref.read(cursorPhotosProvider(_key).notifier);
    final title = widget.label ?? widget.lens ?? widget.camera ?? '';

    Widget stat(String value, String label) => Padding(
      padding: const EdgeInsets.only(right: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: font(18, weight: 700, color: p.ink, tabular: true)),
          Text(label, style: font(12, color: p.inkMuted)),
        ],
      ),
    );

    return Scaffold(
      appBar: pageBar(context, title, sub: t(isLens ? 'gear.lens_sub' : 'gear.camera_sub'), intro: 'gear'),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(gearStatsProvider((widget.camera, widget.lens)));
          await ctrl.refresh();
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) => loadMoreOnScroll(n, ctrl.loadMore),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (stats != null)
                SliverToBoxAdapter(
                  child: SectionCard(
                    margin: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          stat(nf.format(stats.photoCount), t('gear.photos')),
                          stat(nf.format(stats.photographerCount), t('gear.photographers')),
                          if (stats.shutter != null) stat(formatShutter(stats.shutter, locale)!, t('gear.median_shutter')),
                          if (stats.aperture != null) stat(formatAperture(stats.aperture)!, t('gear.median_aperture')),
                          if (stats.iso != null) stat('${stats.iso}', t('gear.median_iso')),
                        ],
                      ),
                    ),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                sliver: SliverToBoxAdapter(
                  child: Wrap(
                    spacing: 6,
                    children: [
                      PillChip(label: t('gear.sort_recent'), selected: _sort == 'recent', onTap: () => setState(() => _sort = 'recent')),
                      PillChip(label: t('gear.sort_popular'), selected: _sort == 'popular', onTap: () => setState(() => _sort = 'popular')),
                    ],
                  ),
                ),
              ),
              if (stats != null && stats.topTags.isNotEmpty)
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 48,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      children: [
                        PillChip(label: t('gear.tag_all'), selected: _tag == null, onTap: () => setState(() => _tag = null)),
                        for (final x in stats.topTags)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: PillChip(
                              label: '#${x.tag}',
                              selected: _tag == x.tag,
                              onTap: () => setState(() => _tag = _tag == x.tag ? null : x.tag),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              if (pages.initialLoading)
                const SliverToBoxAdapter(
                  child: Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
                )
              else if (pages.items.isEmpty && pages.error != null)
                SliverToBoxAdapter(child: ErrorView(error: pages.error!, onRetry: ctrl.refresh))
              else if (pages.items.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(t('gear.empty'), style: font(15, color: p.inkMuted)),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  sliver: _GearColumns(photos: pages.items),
                ),
              if (stats != null && stats.topPhotographers.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                    child: Material(
                      color: p.surface,
                      borderRadius: BorderRadius.circular(18),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => _photographers(stats),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          child: Row(
                            children: [
                              Icon(LucideIcons.users, size: 20, color: p.accentText),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  t(isLens ? 'gear.used_by_lens' : 'gear.used_by_camera', {'count': nf.format(stats.photographerCount)}),
                                  style: font(13.5, color: p.ink),
                                ),
                              ),
                              AvatarStack(users: stats.topPhotographers, size: 24, max: 4),
                              const SizedBox(width: 6),
                              Icon(LucideIcons.chevronRight, size: 20, color: p.inkSubtle),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (pages.loading && pages.items.isNotEmpty)
                const SliverToBoxAdapter(
                  child: Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ),
        ),
      ),
    );
  }
}

/// İki sütun, kendi oranında kareler; köşede pozlama hapı.
class _GearColumns extends StatelessWidget {
  const _GearColumns({required this.photos});
  final List<PhotoCard> photos;

  @override
  Widget build(BuildContext context) {
    final locale = L10n.of(context).locale.languageCode;
    final cols = [<PhotoCard>[], <PhotoCard>[]];
    final h = [0.0, 0.0];
    for (final ph in photos) {
      final c = h[0] <= h[1] ? 0 : 1;
      cols[c].add(ph);
      h[c] += 1 / ph.ratio;
    }
    Widget tile(PhotoCard ph) {
      final img = ph.feed ?? ph.thumb;
      final chip = [formatAperture(ph.exif?.aperture), formatShutter(ph.exif?.shutter, locale)].whereType<String>().join(' · ');
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: GestureDetector(
          onTap: () => context.push('/p/${ph.id}'),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: AspectRatio(
              aspectRatio: ph.ratio,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (img != null) NetPhoto(url: img.url, semanticLabel: ph.title ?? ph.user.displayName),
                  if (chip.isNotEmpty)
                    Positioned(
                      left: 6,
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(999)),
                        child: Text(chip, style: font(10.5, weight: 600, color: Colors.white, tabular: true)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return SliverToBoxAdapter(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Column(children: [for (final ph in cols[0]) tile(ph)])),
          const SizedBox(width: 4),
          Expanded(child: Column(children: [for (final ph in cols[1]) tile(ph)])),
        ],
      ),
    );
  }
}
