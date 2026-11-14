import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/l10n.dart';
import '../core/theme.dart';

/// Yalnızca ekran görüntüsü testlerinde: ağ görsellerini (önbellek eklentisi olmadan) çizer.
@visibleForTesting
Widget Function(String url, BoxFit fit)? debugNetImage;

class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.name, this.url, this.size = 40});
  final String name;
  final String? url;
  final double size;

  String get _initials => name
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .take(2)
      .map((p) => p[0].toUpperCase())
      .join();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (url != null) {
      return ClipOval(
        child: SizedBox(
          width: size,
          height: size,
          child: debugNetImage?.call(url!, BoxFit.cover) ??
              CachedNetworkImage(imageUrl: url!, fit: BoxFit.cover),
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: p.accentTint, shape: BoxShape.circle),
      child: Text(
        _initials,
        style: font(size * 0.38, weight: 700, color: p.accentText),
      ),
    );
  }
}

/// Fotoğraf yüklenirken boşluk değil, hafif bir baskı izi görünür; yüklenince yumuşakça belirir.
class NetPhoto extends StatelessWidget {
  const NetPhoto({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.semanticLabel,
  });
  final String url;
  final BoxFit fit;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      image: true,
      label: semanticLabel,
      child: debugNetImage?.call(url, fit) ?? CachedNetworkImage(
        imageUrl: url,
        fit: fit,
        fadeInDuration: const Duration(milliseconds: 380),
        placeholder: (_, _) => ColoredBox(color: p.surface2),
        errorWidget: (_, _, _) => ColoredBox(color: p.surface2),
      ),
    );
  }
}

class Notice extends StatelessWidget {
  const Notice(
    this.text, {
    super.key,
    this.tone = NoticeTone.info,
    this.action,
  });
  final String text;
  final NoticeTone tone;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final bg = switch (tone) {
      NoticeTone.error => p.danger.withValues(alpha: 0.1),
      NoticeTone.success => p.accentTint,
      NoticeTone.info => p.surface2,
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(Radii.box),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: font(
              15,
              height: 1.4,
              color: tone == NoticeTone.error
                  ? p.danger
                  : (tone == NoticeTone.info ? p.inkMuted : p.ink),
            ),
          ),
          if (action != null)
            Padding(padding: const EdgeInsets.only(top: 4), child: action),
        ],
      ),
    );
  }
}

enum NoticeTone { info, error, success }

/// Hata durumunda tekrar dene butonlu ekran.
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry});
  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final e = ApiException.from(error);
    final message = e.message.isNotEmpty
        ? e.message
        : (e.code == 'network' ? t('common.offline') : t('common.error'));
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton(
                onPressed: onRetry,
                child: Text(t('common.retry')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String errorText(BuildContext context, Object error) {
  final t = L10n.of(context);
  final e = ApiException.from(error);
  if (e.message.isNotEmpty) return e.message;
  return e.code == 'network' ? t('common.offline') : t('common.error');
}

void toast(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));

/// Butonun içinde yükleniyor durumu.
class BusyLabel extends StatelessWidget {
  const BusyLabel({super.key, required this.busy, required this.label});
  final bool busy;
  final String label;

  @override
  Widget build(BuildContext context) => busy
      ? SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: DefaultTextStyle.of(context).style.color,
          ),
        )
      : Text(label);
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.lead});
  final String title;
  final String? lead;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleLarge),
      if (lead != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(lead!, style: Theme.of(context).textTheme.bodySmall),
        ),
    ],
  );
}

const reportReasons = [
  'spam',
  'nudity',
  'violence',
  'harassment',
  'copyright',
  'other',
];

/// Şikayet sebebi seçtirir; seçilen sebebi döndürür (vazgeçilirse null).
Future<String?> pickReportReason(BuildContext context) {
  final t = L10n.of(context);
  return showModalBottomSheet<String>(
    context: context,
    builder: (c) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              t('report.title'),
              style: Theme.of(c).textTheme.titleLarge,
            ),
          ),
          for (final r in reportReasons)
            ListTile(
              title: Text(t('report.reasons.$r')),
              onTap: () => Navigator.pop(c, r),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
