import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../core/l10n.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../state/providers.dart';

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
    final radius = BorderRadius.circular(size * 0.24);
    if (url != null) {
      return ClipRRect(
        borderRadius: radius,
        child: CachedNetworkImage(
          imageUrl: url!,
          width: size,
          height: size,
          fit: BoxFit.cover,
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
      decoration: BoxDecoration(color: p.accent, borderRadius: radius),
      child: Text(
        initials,
        style: font(size * 0.36, weight: 600, color: p.accentInk),
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

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = L10n.of(context);
    final (bg, fg, border) = switch (status) {
      'open' => (p.accent, p.accentInk, null),
      'judging' => (p.ink, p.mat, null),
      'finished' => (Colors.transparent, p.ink, p.ink),
      _ => (Colors.transparent, p.muted, p.line),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: ShapeDecoration(
        color: bg,
        shape: StadiumBorder(
          side: border == null ? BorderSide.none : BorderSide(color: border),
        ),
      ),
      child: Text(
        t('contest.status.$status'),
        style: font(12, weight: 600, color: fg),
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
      color: p.mat,
      child: InkWell(
        onTap: () => context.push('/contests/${c.id}'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  StatusBadge(status: c.status),
                  const SizedBox(width: 8),
                  Text(
                    t('contest.mode.${c.judgingMode}'),
                    style: font(12, color: p.muted),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                c.title,
                style: font(
                  18,
                  weight: 600,
                  height: 1.25,
                  spacing: -0.2,
                  color: p.ink,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 12,
                runSpacing: 2,
                children: [
                  if (showCommunity)
                    Text(c.community.name, style: font(13.5, color: p.muted)),
                  Text(
                    t('contest.entries', {'count': c.entryCount}),
                    style: font(13.5, color: p.muted),
                  ),
                  if (left.isNotEmpty)
                    Text(
                      t(key, {'time': left}),
                      style: font(13.5, weight: 500, color: p.ink),
                    ),
                ],
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
      color: p.mat,
      child: InkWell(
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
                      style: font(13.5, color: p.muted),
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
                    shape: StadiumBorder(side: BorderSide(color: p.line)),
                  ),
                  child: Text(
                    t('community.role.${c.myRole}'),
                    style: font(12, color: p.muted),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Katılım → Değerlendirme → Sonuç; bulunulan adım siyah.
class ContestTimeline extends StatelessWidget {
  const ContestTimeline({super.key, required this.c});
  final ContestCard c;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    final fmt = DateFormat.MMMd(t.locale.languageCode).add_Hm();
    const order = ['open', 'judging', 'closed', 'finished'];
    final current = order
        .indexOf(c.status == 'draft' ? 'open' : c.status)
        .clamp(0, 3);
    final steps = [
      (t('contest.step_entries'), c.submissionDeadline, current == 0),
      (
        c.judgingMode == 'jury'
            ? t('contest.step_jury')
            : t('contest.step_voting'),
        c.votingEnd,
        current == 1 || current == 2,
      ),
      (t('contest.step_results'), c.resultsAt, current == 3),
    ];
    return Container(
      color: p.line,
      child: Row(
        children: [
          for (final (i, (label, at, active)) in steps.indexed) ...[
            if (i > 0) const SizedBox(width: 1),
            Expanded(
              child: Container(
                color: active ? p.ink : p.mat,
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: font(
                        13,
                        weight: 600,
                        color: active ? p.mat : (i < current ? p.ink : p.muted),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      fmt.format(at),
                      style: font(
                        11.5,
                        color: active ? p.mat.withValues(alpha: 0.75) : p.muted,
                      ),
                    ),
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
                      : Icons.star_outline_rounded,
                  size: 30,
                  color: n <= (value ?? 0) ? p.accent : p.muted,
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
                        style: font(15, color: p.muted),
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
