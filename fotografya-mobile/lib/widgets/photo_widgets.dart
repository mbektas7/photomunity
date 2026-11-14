import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../core/l10n.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../state/providers.dart';
import 'common.dart';

class LikeButton extends ConsumerWidget {
  const LikeButton({super.key, required this.photo, this.large = false});
  final PhotoCard photo;
  final bool large;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final s = likeOf(ref, photo);
    final color = s.liked ? p.accent : p.ink;
    return Semantics(
      button: true,
      toggled: s.liked,
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () =>
            ref.read(likeOverridesProvider.notifier).toggle(photo.id, s),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: large ? 14 : 10,
            vertical: large ? 11 : 8,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                transitionBuilder: (c, a) => ScaleTransition(
                  scale: Tween(begin: 0.7, end: 1.0).animate(a),
                  child: c,
                ),
                child: Icon(
                  s.liked ? Icons.favorite : Icons.favorite_border,
                  key: ValueKey(s.liked),
                  color: color,
                  size: large ? 22 : 20,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${s.count}',
                style: font(
                  large ? 15 : 14,
                  weight: 600,
                  color: color,
                  tabular: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class UserRow extends StatelessWidget {
  const UserRow({super.key, required this.user, this.size = 36});
  final UserCard user;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return InkWell(
      onTap: () => context.push('/u/${user.username}'),
      child: Row(
        children: [
          Avatar(name: user.displayName, url: user.avatarUrl, size: size),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: font(15, weight: 600, color: p.ink),
                ),
                Text(
                  '@${user.username}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: font(13, color: p.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Akıştaki tek kare: paspartulu bir baskı gibi, kırpılmadan.
class PhotoPrint extends StatelessWidget {
  const PhotoPrint({super.key, required this.photo});
  final PhotoCard photo;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final img = photo.feed;
    final locale = L10n.of(context).locale.languageCode;
    return ColoredBox(
      color: p.mat,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: UserRow(user: photo.user),
          ),
          if (img != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: GestureDetector(
                onTap: () => context.push('/p/${photo.id}'),
                child: AspectRatio(
                  aspectRatio: img.ratio,
                  child: NetPhoto(url: img.url, semanticLabel: photo.title),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 16, 6),
            child: Row(
              children: [
                LikeButton(photo: photo),
                const Spacer(),
                if (photo.title != null)
                  Flexible(
                    child: Text(
                      photo.title!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: font(13, weight: 500, color: p.ink),
                    ),
                  ),
                if (photo.publishedAt != null) ...[
                  const SizedBox(width: 10),
                  Text(
                    DateFormat.yMMMd(locale)
                        .format(photo.publishedAt!.toLocal()),
                    style: font(13, color: p.muted),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
