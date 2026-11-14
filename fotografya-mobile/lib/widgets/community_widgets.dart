import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../core/l10n.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../state/providers.dart';
import 'common.dart';
import 'design.dart';

/// Topluluk logosu yuvarlatılmış karedir; kişi avatarları yuvarlak — web ile aynı ayrım.
class CommunityLogo extends StatelessWidget {
  const CommunityLogo({
    super.key,
    required this.name,
    this.url,
    this.size = 48,
  });
  final String name;
  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final radius = BorderRadius.circular(size >= 48 ? Radii.photo : size * 0.3);
    if (url != null) {
      return ClipRRect(
        borderRadius: radius,
        child: SizedBox(
          width: size,
          height: size,
          child: NetPhoto(url: url!),
        ),
      );
    }
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .take(2)
        .map((w) => w.isEmpty ? '' : w[0].toUpperCase())
        .join();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: p.accentTint, borderRadius: radius),
      child: Text(
        initials,
        style: font(size * 0.36, weight: 700, color: p.accentText),
      ),
    );
  }
}

String remainingText(DateTime at, String locale) {
  final d = at.difference(DateTime.now());
  if (d.isNegative) return '';
  final tr = locale == 'tr';
  if (d.inDays > 0)
    return tr
        ? '${d.inDays} gün ${d.inHours % 24} saat'
        : '${d.inDays}d ${d.inHours % 24}h';
  if (d.inHours > 0)
    return tr
        ? '${d.inHours} saat ${d.inMinutes % 60} dk'
        : '${d.inHours}h ${d.inMinutes % 60}m';
  return tr ? '${d.inMinutes} dakika' : '${d.inMinutes} min';
}

/// Canlı aşamalar (katılım, oylama) live rozeti; diğerleri sakin hap.
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.status,
    this.mode,
    this.small = false,
  });
  final String status;
  final String? mode;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = L10n.of(context);
    if (status == 'open' || status == 'judging') {
      return LiveBadge(
        status == 'open'
            ? t('contest.phase_open')
            : (mode == 'jury'
                  ? t('contest.phase_jury')
                  : t('contest.phase_voting')),
        small: small,
      );
    }
    return Container(
      height: small ? 20 : 28,
      padding: EdgeInsets.symmetric(horizontal: small ? 7 : 11),
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        color: p.surface2,
        shape: const StadiumBorder(),
      ),
      child: Text(
        t('contest.status.$status'),
        style: font(small ? 11 : 13, weight: 600, color: p.inkMuted),
      ),
    );
  }
}

class ContestTile extends StatelessWidget {
  const ContestTile({super.key, required this.c, this.showCommunity = true});
  final ContestCard c;
  final bool showCommunity;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    final locale = t.locale.languageCode;
    final (key, at) = switch (c.status) {
      'open' || 'draft' => ('contest.deadline_in', c.submissionDeadline),
      'judging' => ('contest.voting_ends_in', c.votingEnd),
      'closed' => ('contest.results_in', c.resultsAt),
      _ => ('', c.resultsAt),
    };
    final left = key.isEmpty ? '' : remainingText(at, locale);
    return Material(
      color: p.surface,
      borderRadius: BorderRadius.circular(Radii.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.card),
        onTap: () => context.push('/contests/${c.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CommunityLogo(name: c.community.name, url: c.community.logoUrl, size: 60),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        StatusBadge(status: c.status, mode: c.judgingMode, small: true),
                        if (left.isNotEmpty)
                          Text(
                            t(key, {'time': left}),
                            style: AppText.caption(p.inkMuted),
                          ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      c.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: font(17, weight: 700, spacing: -0.2, color: p.ink),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (showCommunity) c.community.name,
                        t('contest.entries', {'count': c.entryCount}),
                      ].join('  ·  '),
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
    );
  }
}

class CommunityTile extends StatelessWidget {
  const CommunityTile({super.key, required this.c});
  final CommunityCard c;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    final meta = [
      ?c.city,
      t('community.members', {'count': c.memberCount}),
    ].join('  ·  ');
    return Material(
      color: p.surface,
      borderRadius: BorderRadius.circular(Radii.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.card),
        onTap: () => context.push('/c/${c.slug}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              CommunityLogo(name: c.name, url: c.logoUrl, size: 50),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: font(16, weight: 600, color: p.ink),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: font(13.5, color: p.inkMuted),
                    ),
                  ],
                ),
              ),
              if (c.myRole != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 3,
                  ),
                  decoration: ShapeDecoration(
                    color: p.surface2,
                    shape: const StadiumBorder(),
                  ),
                  child: Text(
                    t('community.role.${c.myRole}'),
                    style: font(12, weight: 600, color: p.inkMuted),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Katılım → Oylama/Jüri → Sonuç. Üstte çubuk: geçmiş accent, şu an live, gelecek line.
class ContestTimeline extends StatelessWidget {
  const ContestTimeline({super.key, required this.c});
  final ContestCard c;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    final fmt = DateFormat.MMMd(t.locale.languageCode);
    const order = ['open', 'judging', 'closed', 'finished'];
    final current = order
        .indexOf(c.status == 'draft' ? 'open' : c.status)
        .clamp(0, 3);
    final steps = [
      (t('contest.step_entries'), c.submissionDeadline, 0),
      (
        c.judgingMode == 'jury'
            ? t('contest.step_jury')
            : t('contest.step_voting'),
        c.votingEnd,
        1,
      ),
      (t('contest.step_results'), c.resultsAt, 3),
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, (label, at, idx)) in steps.indexed) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(
            child: Builder(
              builder: (_) {
                final active = current == idx || (idx == 1 && current == 2);
                final done = !active && current > idx;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 4,
                      decoration: ShapeDecoration(
                        color: active ? p.live : (done ? p.accent : p.line),
                        shape: const StadiumBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(label, style: font(13.5, weight: 700, color: p.ink)),
                    const SizedBox(height: 2),
                    Text(fmt.format(at), style: AppText.caption(p.inkMuted)),
                  ],
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

class StarRating extends StatelessWidget {
  const StarRating({super.key, required this.value, required this.onChanged});
  final int? value;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = L10n.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var n = 1; n <= 5; n++)
          Semantics(
            button: true,
            selected: value == n,
            label: t('contest.stars', {'count': n}),
            child: InkResponse(
              onTap: onChanged == null ? null : () => onChanged!(n),
              radius: 22,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  n <= (value ?? 0)
                      ? Icons.star_rounded
                      : LucideIcons.star,
                  size: 30,
                  color: n <= (value ?? 0) ? p.accent : p.inkMuted,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Kullanıcının yayındaki fotoğraflarından birini seçtirir.
Future<PhotoCard?> pickMyPhoto(
  BuildContext context,
  WidgetRef ref,
  String title,
) async {
  final me = ref.read(authProvider).asData?.value;
  if (me == null) return null;
  return showModalBottomSheet<PhotoCard>(
    context: context,
    isScrollControlled: true,
    builder: (c) => _PhotoPicker(username: me.username, title: title),
  );
}

class _PhotoPicker extends ConsumerWidget {
  const _PhotoPicker({required this.username, required this.title});
  final String username;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = L10n.of(context);
    final p = context.palette;
    final pages = ref.watch(photoPagesProvider('users/$username/photos'));
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(title, style: Theme.of(context).textTheme.titleLarge),
            ),
            Expanded(
              child: pages.initialLoading
                  ? const Center(child: CircularProgressIndicator())
                  : pages.items.isEmpty
                  ? Center(
                      child: Text(
                        t('contest.no_photos'),
                        style: font(15, color: p.inkMuted),
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: 4,
                            crossAxisSpacing: 4,
                          ),
                      itemCount: pages.items.length,
                      itemBuilder: (_, i) {
                        final photo = pages.items[i];
                        return GestureDetector(
                          onTap: () => Navigator.pop(context, photo),
                          child: CachedNetworkImage(
                            imageUrl: photo.thumb!.url,
                            fit: BoxFit.cover,
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
