import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../core/l10n.dart';
import '../core/theme.dart';
import '../state/providers.dart';

/// Akış içi reklam (300×250). Pro kullanıcıya, izin yoksa ya da reklam yüklenemezse hiç yer kaplamaz.
/// Bilinçli olarak yalnızca akışta ve rehberde kullanılır; fotoğraf detayı, mesajlar, AR ve oylama reklamsızdır.
class InlineAd extends ConsumerStatefulWidget {
  const InlineAd({super.key});

  @override
  ConsumerState<InlineAd> createState() => _InlineAdState();
}

class _InlineAdState extends ConsumerState<InlineAd> {
  BannerAd? _ad;
  bool _loaded = false;

  void _load() {
    if (_ad != null) return;
    _ad = BannerAd(
      adUnitId: ref.read(adsProvider).bannerUnit,
      size: AdSize.mediumRectangle,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, _) {
          ad.dispose();
          _ad = null;
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authProvider).asData?.value;
    final ads = ref.watch(adsProvider);
    if (me?.isPro ?? false) return const SizedBox.shrink();
    return ValueListenableBuilder<bool>(
      valueListenable: ads.ready,
      builder: (context, ready, _) {
        if (!ready) return const SizedBox.shrink();
        _load();
        if (!_loaded || _ad == null) return const SizedBox.shrink();
        final t = L10n.of(context);
        final p = context.palette;
        return Container(
          color: p.mat,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(
            children: [
              Row(
                children: [
                  Text(t('ads.label'), style: font(11, color: p.muted)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => context.push('/pro'),
                    child: Text(
                      t('ads.remove'),
                      style: font(11, weight: 600, color: p.muted),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(width: 300, height: 250, child: AdWidget(ad: _ad!)),
            ],
          ),
        );
      },
    );
  }
}

class ProBadge extends StatelessWidget {
  const ProBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: p.accent,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        'PRO',
        style: font(10, weight: 700, spacing: 0.6, color: p.accentInk),
      ),
    );
  }
}
