import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/l10n.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../state/providers.dart';
import '../widgets/common.dart';
import '../widgets/design.dart';

/// Tam ekran yakınlaştırma: en büyük türev (images.full), çift dokunuşla 1:1, mini harita ve EXIF şeridi.
class ZoomScreen extends ConsumerWidget {
  const ZoomScreen({super.key, required this.photoId});
  final String photoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(photoProvider(photoId));
    final photo = async.asData?.value;
    return Scaffold(
      backgroundColor: Colors.black,
      body: photo?.full != null
          ? _Viewer(photo: photo!)
          : async.hasError
          ? SafeArea(child: ErrorView(error: async.error!, onRetry: () => ref.invalidate(photoProvider(photoId))))
          : const Center(child: CircularProgressIndicator(color: Colors.white)),
    );
  }
}

class _Viewer extends StatefulWidget {
  const _Viewer({required this.photo});
  final PhotoDetail photo;

  @override
  State<_Viewer> createState() => _ViewerState();
}

class _ViewerState extends State<_Viewer> with SingleTickerProviderStateMixin {
  final _ctrl = TransformationController();
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
  Animation<Matrix4>? _tween;
  Offset _tap = Offset.zero;
  bool _hint = true;
  Timer? _hintTimer;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() => setState(() {}));
    _anim.addListener(() {
      if (_tween != null) _ctrl.value = _tween!.value;
    });
    _hintTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _hint = false);
    });
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    _anim.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _animateTo(Matrix4 target) {
    _tween = Matrix4Tween(begin: _ctrl.value, end: target).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOut));
    _anim.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final img = widget.photo.full!;
    final locale = t.locale.languageCode;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final pad = MediaQuery.paddingOf(context);
    return LayoutBuilder(
      builder: (context, box) {
        final vw = box.maxWidth, vh = box.maxHeight;
        // Ekrana sığan boyut (kırpma yok)
        final fit = vw / vh > img.ratio ? Size(vh * img.ratio, vh) : Size(vw, vw / img.ratio);
        final imageRect = Rect.fromCenter(center: Offset(vw / 2, vh / 2), width: fit.width, height: fit.height);
        // 1:1 = görselin bir pikseli ekranın bir fiziksel pikseli
        final oneToOne = math.max(1.0, img.width / (fit.width * dpr));
        final scale = _ctrl.value.getMaxScaleOnAxis();
        final pct = (scale / (img.width / (fit.width * dpr)) * 100).round();
        final atOne = (scale - oneToOne).abs() / oneToOne < 0.03;

        // Görünen bölge (görsel koordinatında, 0–1)
        final inv = Matrix4.inverted(_ctrl.value);
        final tl = MatrixUtils.transformPoint(inv, Offset.zero);
        final br = MatrixUtils.transformPoint(inv, Offset(vw, vh));
        final vis = Rect.fromPoints(tl, br).intersect(imageRect);
        final norm = Rect.fromLTRB(
          (vis.left - imageRect.left) / imageRect.width,
          (vis.top - imageRect.top) / imageRect.height,
          (vis.right - imageRect.left) / imageRect.width,
          (vis.bottom - imageRect.top) / imageRect.height,
        );
        const mapW = 96.0;
        final mapH = mapW / img.ratio;

        final exif = widget.photo.exif;
        final exposure = [
          formatShutter(exif?.shutter, locale),
          formatAperture(exif?.aperture),
          if (exif?.iso != null) 'ISO ${exif!.iso}',
        ].whereType<String>().join(' · ');
        final strip = [
          if (exif?.camera != null) (t('zoom.camera'), exif!.camera!),
          if (exif?.lens != null || exif?.focalLength != null) (t('zoom.lens'), exif!.lens ?? formatFocal(exif.focalLength)!),
          if (exposure.isNotEmpty) (t('zoom.exposure'), exposure),
        ];

        return Stack(
          children: [
            GestureDetector(
              onDoubleTapDown: (d) => _tap = d.localPosition,
              onDoubleTap: () {
                if (scale > 1.05) {
                  _animateTo(Matrix4.identity());
                } else {
                  final s = math.max(oneToOne, 2.0);
                  _animateTo(Matrix4.identity()
                    ..translateByDouble(-_tap.dx * (s - 1), -_tap.dy * (s - 1), 0, 1)
                    ..scaleByDouble(s, s, 1, 1));
                }
              },
              child: InteractiveViewer(
                transformationController: _ctrl,
                minScale: 1,
                maxScale: math.max(4.0, oneToOne * 2),
                child: SizedBox(
                  width: vw,
                  height: vh,
                  child: Center(
                    child: SizedBox.fromSize(
                      size: fit,
                      child: NetPhoto(url: img.url, fit: BoxFit.contain, semanticLabel: widget.photo.title),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              top: pad.top + 8,
              child: Row(
                children: [
                  _Glass(
                    child: IconButton(
                      tooltip: t('ui.back'),
                      icon: const Icon(LucideIcons.chevronLeft, color: Colors.white),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                  const Spacer(),
                  _Glass(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Text(
                        atOne ? '%$pct · 1:1' : '%$pct',
                        style: font(13, weight: 700, color: Colors.white, tabular: true),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (scale > 1.05 && widget.photo.thumb != null)
              Positioned(
                right: 16,
                top: pad.top + 66,
                child: IgnorePointer(
                  child: Container(
                    width: mapW,
                    height: mapH,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 1.5),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        NetPhoto(url: widget.photo.thumb!.url, fit: BoxFit.fill),
                        Positioned(
                          left: norm.left * mapW,
                          top: norm.top * mapH,
                          width: math.max(4, norm.width * mapW),
                          height: math.max(4, norm.height * mapH),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.white, width: 2),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (_hint && scale <= 1.05)
              Positioned(
                left: 0,
                right: 0,
                bottom: pad.bottom + (strip.isEmpty ? 40 : 120),
                child: IgnorePointer(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(999)),
                      child: Text(t('zoom.hint'), style: font(13, color: Colors.white)),
                    ),
                  ),
                ),
              ),
            if (strip.isNotEmpty)
              Positioned(
                left: 12,
                right: 12,
                bottom: pad.bottom + 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(color: const Color(0xD914161B), borderRadius: BorderRadius.circular(20)),
                  child: Row(
                    children: [
                      for (final (i, (label, value)) in strip.indexed) ...[
                        if (i > 0) const SizedBox(width: 12),
                        Expanded(
                          flex: label == t('zoom.exposure') ? 3 : 2,
                          child: Column(
                            children: [
                              Text(label, style: font(12.5, color: Colors.white60)),
                              Text(value, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis,
                                  style: font(14, weight: 700, color: Colors.white)),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Glass extends StatelessWidget {
  const _Glass({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white.withValues(alpha: 0.14),
    shape: const StadiumBorder(),
    child: child,
  );
}
