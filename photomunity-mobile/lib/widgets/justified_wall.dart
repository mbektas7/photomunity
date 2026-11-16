import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/models.dart';
import 'common.dart';

const _gap = 4.0;

class WallRow {
  WallRow(this.height, this.items);
  final double height;
  final List<(PhotoCard, double)> items; // fotoğraf, genişlik
}

/// Kareleri asla kırpmadan, her birini kendi en-boy oranında satırlara dizer (web ile aynı algoritma).
List<WallRow> buildRows(List<PhotoCard> photos, double width, double target) {
  final rows = <WallRow>[];
  var current = <PhotoCard>[];
  var sum = 0.0;
  for (final p in photos) {
    current.add(p);
    sum += p.ratio;
    final h = (width - _gap * (current.length - 1)) / sum;
    if (h <= target) {
      rows.add(WallRow(h, [for (final c in current) (c, c.ratio * h)]));
      current = [];
      sum = 0;
    }
  }
  if (current.isNotEmpty) {
    final h = ((width - _gap * (current.length - 1)) / sum).clamp(0.0, target);
    rows.add(WallRow(h, [for (final c in current) (c, c.ratio * h)]));
  }
  return rows;
}

class SliverJustifiedWall extends StatelessWidget {
  const SliverJustifiedWall({
    super.key,
    required this.photos,
    this.target = 190,
    this.completeRowsOnly = false,
  });
  final List<PhotoCard> photos;
  final double target;
  final bool completeRowsOnly;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.crossAxisExtent;
        var rows = buildRows(photos, width, target);
        if (completeRowsOnly && rows.length > 1) {
          final last = rows.last;
          final used = last.items.fold<double>(0, (s, i) => s + i.$2);
          if (used < width * 0.9) rows = rows.sublist(0, rows.length - 1);
        }
        return SliverList.separated(
          itemCount: rows.length,
          separatorBuilder: (_, _) => const SizedBox(height: _gap),
          itemBuilder: (context, i) {
            final row = rows[i];
            return SizedBox(
              height: row.height,
              child: Row(
                children: [
                  for (final (index, (photo, w)) in row.items.indexed) ...[
                    if (index > 0) const SizedBox(width: _gap),
                    SizedBox(
                      width: w,
                      child: GestureDetector(
                        onTap: () => context.push('/p/${photo.id}'),
                        child: NetPhoto(
                          url:
                              ((row.height > 260 ? photo.feed : photo.thumb) ??
                                      photo.feed)!
                                  .url,
                          semanticLabel: photo.title ?? photo.user.displayName,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}
