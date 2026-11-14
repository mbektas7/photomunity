import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/config.dart';
import '../core/l10n.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../state/providers.dart';
import 'common.dart';

// "Canlı topluluk" ortak bileşenleri (design/components/*.md).

/// Kart: bg üzerinde surface, radius-card, gölge yok.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Space.s3),
    this.color,
    this.radius = Radii.card,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: color ?? context.palette.surface,
      borderRadius: BorderRadius.circular(radius),
    ),
    child: child,
  );
}

// ---------------------------------------------------------------- ExifChip

/// API uzun pozları `15"` biçiminde verir; ekranda "15 sn" / "15 s".
String? formatShutter(String? v, String locale) {
  if (v == null) return null;
  final m = RegExp(r'^([\d.,]+)"$').firstMatch(v);
  if (m == null) return v;
  final n = locale == 'tr' ? m.group(1)!.replaceAll('.', ',') : m.group(1)!;
  return '$n ${locale == 'tr' ? 'sn' : 's'}';
}

String? formatAperture(double? a) {
  if (a == null) return null;
  final s = a.toStringAsFixed(1);
  return 'f/${s.endsWith('.0') ? s.substring(0, s.length - 2) : s}';
}

String? formatFocal(double? mm) => mm == null ? null : '${mm.round()}mm';

/// Kart altı çipleri: diyafram, enstantane, ISO; yer kalırsa odak. Boşlar atlanır.
List<String> exifChips(Exif? e, String locale, {int max = 3}) {
  if (e == null) return const [];
  return [
    formatAperture(e.aperture),
    formatShutter(e.shutter, locale),
    if (e.iso != null) 'ISO ${e.iso}',
    formatFocal(e.focalLength),
  ].whereType<String>().take(max).toList();
}

/// Fotoğrafın çekim bilgisini gösteren küçük hap; uygulamanın imzası.
class ExifChip extends StatelessWidget {
  const ExifChip(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        color: p.surface2,
        shape: const StadiumBorder(),
      ),
      child: Text(
        text,
        style: font(12.5, weight: 600, color: p.inkMuted, tabular: true),
      ),
    );
  }
}

// ---------------------------------------------------------------- Live / Countdown

/// Yalnızca zamanla ilgili canlı durumlar için turuncu rozet.
class LiveBadge extends StatelessWidget {
  const LiveBadge(this.text, {super.key, this.small = false});
  final String text;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      height: small ? 20 : 28,
      padding: EdgeInsets.symmetric(horizontal: small ? 7 : 11),
      alignment: Alignment.center,
      decoration: ShapeDecoration(color: p.live, shape: const StadiumBorder()),
      child: Text(
        text,
        style: font(small ? 11 : 13.5, weight: 700, color: p.liveInk),
      ),
    );
  }
}

/// Bir sonraki aşamaya kalan süre: gün/saat/dakika; bir günün altında saat/dakika/saniye.
class Countdown extends StatefulWidget {
  const Countdown({super.key, required this.until, required this.srLabel});
  final DateTime until;

  /// Ekran okuyucu cümlesinin başı ("Oylamanın kapanmasına").
  final String srLabel;

  @override
  State<Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<Countdown> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = L10n.of(context);
    var d = widget.until.difference(DateTime.now());
    if (d.isNegative) d = Duration.zero;
    final underDay = d.inDays == 0;
    final boxes = underDay
        ? [
            (d.inHours, t('ui.hours')),
            (d.inMinutes % 60, t('ui.minutes')),
            (d.inSeconds % 60, t('ui.seconds')),
          ]
        : [
            (d.inDays, t('ui.days')),
            (d.inHours % 24, t('ui.hours')),
            (d.inMinutes % 60, t('ui.minutes')),
          ];
    return Semantics(
      label: t('ui.countdown_sr', {
        'label': widget.srLabel,
        'days': d.inDays,
        'hours': d.inHours % 24,
        'minutes': d.inMinutes % 60,
      }),
      excludeSemantics: true,
      child: Row(
        children: [
          for (final (i, b) in boxes.indexed) ...[
            if (i > 0) const SizedBox(width: Space.s2),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: p.surface2,
                  borderRadius: BorderRadius.circular(Radii.box),
                ),
                child: Column(
                  children: [
                    Text(
                      b.$1.toString().padLeft(2, '0'),
                      style: AppText.numeral(p.ink),
                    ),
                    const SizedBox(height: 4),
                    Text(b.$2, style: AppText.caption(p.inkMuted)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// "3 gün" / "5 sa" gibi kısa kalan süre (hikâye rozeti), ve "3 gün kaldı".
(String short, String left)? shortRemaining(L10n t, DateTime at) {
  final d = at.difference(DateTime.now());
  if (d.isNegative) return null;
  if (d.inDays > 0) {
    return (
      t('ui.days_short', {'count': d.inDays}),
      t('ui.days_left', {'count': d.inDays}),
    );
  }
  if (d.inHours > 0) {
    return (
      t('ui.hours_short', {'count': d.inHours}),
      t('ui.hours_left', {'count': d.inHours}),
    );
  }
  final m = d.inMinutes < 1 ? 1 : d.inMinutes;
  return (
    t('ui.minutes_short', {'count': m}),
    t('ui.minutes_left', {'count': m}),
  );
}

/// Yarışmanın sıradaki anı: katılımda son gönderim, oylamada oylama bitişi.
DateTime? contestNextMoment(ContestCard c) => switch (c.status) {
  'open' || 'draft' => c.submissionDeadline,
  'judging' => c.votingEnd,
  'closed' => c.resultsAt,
  _ => null,
};

// ---------------------------------------------------------------- StoryRing

enum RingState { live, accent, idle }

/// Akışın üstündeki yuvarlak topluluk / yarışma kısayolu. Görsel daire içinde kırpılır.
class StoryRing extends StatelessWidget {
  const StoryRing({
    super.key,
    required this.label,
    required this.state,
    required this.onTap,
    this.image,
    this.badge,
    this.semanticLabel,
    this.size = 64,
  });
  final String label;
  final RingState state;
  final VoidCallback onTap;
  final String? image;
  final String? badge;
  final String? semanticLabel;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final ring = switch (state) {
      RingState.live => p.live,
      RingState.accent => p.accent,
      RingState.idle => p.ringIdle,
    };
    final initials = label
        .trim()
        .split(RegExp(r'\s+'))
        .take(2)
        .map((w) => w.isEmpty ? '' : w[0].toUpperCase())
        .join();
    return Semantics(
      button: true,
      label: semanticLabel ?? label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.box),
        child: SizedBox(
          width: size + 8,
          child: Column(
            children: [
              SizedBox(
                width: size,
                height: size + (badge != null ? 6 : 0),
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.topCenter,
                  children: [
                    Container(
                      width: size,
                      height: size,
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: ring,
                        shape: BoxShape.circle,
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: p.bg, width: 2),
                          color: p.surface2,
                        ),
                        clipBehavior: Clip.antiAlias,
                        alignment: Alignment.center,
                        child: image != null
                            ? NetPhoto(url: image!)
                            : Text(
                                initials,
                                style: font(
                                  size * 0.26,
                                  weight: 700,
                                  color: p.inkMuted,
                                ),
                              ),
                      ),
                    ),
                    if (badge != null)
                      Positioned(
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: p.live,
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(color: p.bg, width: 2),
                          ),
                          child: Text(
                            badge!,
                            style: font(11, weight: 700, color: p.liveInk),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 7),
              Text(
                label,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: font(12.5, weight: 500, height: 1.15, color: p.ink),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Buttons

/// Yuvarlak ikincil düğme (Paylaş, Diğer): surface-2 zemin ya da fotoğraf üstünde buzlu cam.
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.size = 44,
    this.scrim = false,
    this.color,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final double size;
  final bool scrim;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final button = Material(
      color: scrim ? p.scrim : (color ?? p.surface2),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: size * 0.44, color: p.ink),
        ),
      ),
    );
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: scrim
          ? ClipOval(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: button,
              ),
            )
          : button,
    );
  }
}

/// Paylaş: bağlantıyı panoya kopyalar (uygulamanın mevcut paylaşım davranışı).
class ShareButton extends StatelessWidget {
  const ShareButton({
    super.key,
    required this.path,
    this.title,
    this.size = 38,
    this.scrim = false,
  });
  final String path;
  final String? title;
  final double size;
  final bool scrim;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    return RoundIconButton(
      icon: LucideIcons.share2,
      label: t('ui.share'),
      size: size,
      scrim: scrim,
      onPressed: () async {
        await Clipboard.setData(
          ClipboardData(text: '${AppConfig.webUrl}/${t.locale.languageCode}$path'),
        );
        if (context.mounted) toast(context, t('ui.link_copied'));
      },
    );
  }
}

/// Ekranın altındaki ana çağrı (Button large): 56 px, radius-box, accent.
class LargeButton extends StatelessWidget {
  const LargeButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SizedBox(
      height: 56,
      width: double.infinity,
      child: FilledButton(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.box),
          ),
          textStyle: font(17, weight: 700),
        ),
        onPressed: busy ? null : onPressed,
        child: busy
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: p.accentInk,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 22),
                    const SizedBox(width: 10),
                  ],
                  Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
                ],
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Like

/// Beğeni hapı: beğenilmişse accent-tint zemin ve accent dolgulu kalp.
class LikePill extends ConsumerWidget {
  const LikePill({super.key, required this.photo, this.wide = false});
  final PhotoCard photo;

  /// Detaydaki geniş düğme ("Beğendin, 248").
  final bool wide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final t = L10n.of(context);
    final s = likeOf(ref, photo);
    final fg = s.liked ? p.accentText : p.ink;
    final label = wide && s.liked
        ? t('photo.liked_count', {'count': s.count})
        : '${s.count}';
    return Semantics(
      button: true,
      toggled: s.liked,
      label: s.liked
          ? t('photo.unlike_count', {'count': s.count})
          : t('photo.like_count', {'count': s.count}),
      excludeSemantics: true,
      child: Material(
        color: s.liked ? p.accentTint : p.surface2,
        shape: wide
            ? RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Radii.box),
              )
            : const StadiumBorder(),
        child: InkWell(
          customBorder: wide
              ? RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Radii.box),
                )
              : const StadiumBorder(),
          onTap: () =>
              ref.read(likeOverridesProvider.notifier).toggle(photo.id, s),
          child: SizedBox(
            height: wide ? 52 : 38,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: wide ? 20 : 14),
              child: Row(
                mainAxisSize: wide ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    transitionBuilder: (c, a) => ScaleTransition(
                      scale: Tween(begin: 0.7, end: 1.0).animate(a),
                      child: c,
                    ),
                    child: Icon(
                      s.liked ? Icons.favorite : LucideIcons.heart,
                      key: ValueKey(s.liked),
                      color: s.liked ? p.accent : p.ink,
                      size: wide ? 21 : 19,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    label,
                    style: font(
                      wide ? 16 : 14.5,
                      weight: wide ? 700 : 600,
                      color: fg,
                      tabular: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- PhotoCard

/// Akış kartı: yazar, kırpılmamış kare, beğeni, paylaş ve en fazla üç ExifChip.
/// API'nin akış yanıtında exif, konum ve takip durumu yok; gelirse gösterilir, gelmezse çizilmez.
class PhotoCardView extends StatelessWidget {
  const PhotoCardView({
    super.key,
    required this.photo,
    this.exif,
    this.place,
    this.trailing,
  });
  final PhotoCard photo;
  final Exif? exif;
  final String? place;

  /// Başlık satırının sağı (ör. yalnızca takip edilmeyen yazarda Takip et).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = L10n.of(context);
    final locale = t.locale.languageCode;
    final img = photo.feed;
    final when = photo.publishedAt == null
        ? null
        : relativeTime(photo.publishedAt!, locale);
    final meta = [place, when].whereType<String>().join(', ');
    final chips = exifChips(exif, locale);
    return SurfaceCard(
      padding: const EdgeInsets.all(Space.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 12),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(Radii.box),
                    onTap: () => context.push('/u/${photo.user.username}'),
                    child: Row(
                      children: [
                        Avatar(
                          name: photo.user.displayName,
                          url: photo.user.avatarUrl,
                          size: 38,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                photo.user.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.bodyStrong(p.ink),
                              ),
                              if (meta.isNotEmpty)
                                Text(
                                  meta,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppText.caption(p.inkMuted),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
          if (img != null)
            GestureDetector(
              onTap: () => context.push('/p/${photo.id}'),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Radii.photo),
                child: AspectRatio(
                  aspectRatio: img.ratio,
                  child: NetPhoto(url: img.url, semanticLabel: photo.title),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 2),
            child: Row(
              children: [
                LikePill(photo: photo),
                const SizedBox(width: Space.s2),
                ShareButton(path: '/p/${photo.id}', title: photo.title),
                const Spacer(),
                for (final (i, c) in chips.indexed) ...[
                  if (i > 0) const SizedBox(width: 6),
                  ExifChip(c),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "2 sa önce", "dün" gibi göreli zaman.
String relativeTime(DateTime at, String locale) {
  final d = DateTime.now().difference(at);
  final tr = locale == 'tr';
  if (d.inMinutes < 1) return tr ? 'şimdi' : 'just now';
  if (d.inHours < 1) return tr ? '${d.inMinutes} dk önce' : '${d.inMinutes}m ago';
  if (d.inDays < 1) return tr ? '${d.inHours} sa önce' : '${d.inHours}h ago';
  if (d.inDays == 1) return tr ? 'dün' : 'yesterday';
  if (d.inDays < 7) return tr ? '${d.inDays} gün önce' : '${d.inDays}d ago';
  if (d.inDays < 30) {
    final w = d.inDays ~/ 7;
    return tr ? '$w hafta önce' : '${w}w ago';
  }
  final m = d.inDays ~/ 30;
  if (m < 12) return tr ? '$m ay önce' : '${m}mo ago';
  final y = d.inDays ~/ 365;
  return tr ? '$y yıl önce' : '${y}y ago';
}

// ---------------------------------------------------------------- BottomNav

/// Yüzen alt menü: Akış, Keşfet, (Yükle), Yarışmalar, Profil. Etiket yok; Semantics etiketli.
class FloatingBottomNav extends StatelessWidget {
  const FloatingBottomNav({
    super.key,
    required this.current,
    required this.onSelect,
  });

  /// Etkin hedef: 0 akış, 1 keşfet, 2 yükle, 3 yarışmalar, 4 profil.
  final int current;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = L10n.of(context);
    final bottom = MediaQuery.paddingOf(context).bottom;
    Widget item(int i, IconData icon, String label) {
      final active = current == i;
      return Expanded(
        child: Semantics(
          button: true,
          selected: active,
          label: label,
          excludeSemantics: true,
          child: InkResponse(
            onTap: () => onSelect(i),
            radius: 28,
            child: SizedBox(
              height: 66,
              child: Icon(
                icon,
                size: 26,
                color: active ? p.ink : p.inkSubtle,
                weight: active ? IconStroke.active : IconStroke.normal,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(12, 0, 12, bottom > 0 ? bottom : 12),
      child: SizedBox(
        height: 66 + 22,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            Container(
              height: 66,
              decoration: BoxDecoration(
                color: p.surface,
                borderRadius: BorderRadius.circular(Radii.card),
                boxShadow: p.shadowFloat,
              ),
              child: Row(
                children: [
                  item(0, LucideIcons.house, t('nav.feed')),
                  item(1, LucideIcons.compass, t('nav.explore')),
                  const Expanded(child: SizedBox()),
                  item(3, LucideIcons.trophy, t('nav.contests')),
                  item(4, LucideIcons.userRound, t('nav.profile')),
                ],
              ),
            ),
            Positioned(
              top: 0,
              child: Semantics(
                button: true,
                selected: current == 2,
                label: t('nav.upload'),
                excludeSemantics: true,
                child: GestureDetector(
                  onTap: () => onSelect(2),
                  child: Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: p.accent,
                      shape: BoxShape.circle,
                      boxShadow: p.shadowAccent,
                    ),
                    child: Icon(LucideIcons.plus, size: 28, color: p.accentInk),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
