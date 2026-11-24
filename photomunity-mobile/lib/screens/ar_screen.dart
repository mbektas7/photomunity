import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:sensors_plus/sensors_plus.dart';

import '../core/ar_math.dart';
import '../core/astro.dart';
import '../core/l10n.dart';
import '../core/sky.dart';
import '../core/theme.dart';
import '../widgets/intro.dart';
import 'sky/ar_widgets.dart';
import 'sky/sky_common.dart';

/// Telefonu gökyüzüne tut: kamera görüntüsü üzerinde Samanyolu çekirdeğinin ve Ay'ın bu gecelik yolu.
///
/// Yönelim ivmeölçer (yerçekimi) + manyetometreden hesaplanır (ar_math.dart). Telefon pusulası
/// birkaç derece sapabilir ve manyetik sapma konuma göre değişir; bu yüzden iki kalibrasyon var:
/// "Ay'a hizala" (Ay'ı ortaya getirip dokun) ve görüş açısı ayarı.
class ArSkyScreen extends StatefulWidget {
  const ArSkyScreen({
    super.key,
    required this.lat,
    required this.lng,
    required this.date,
  });
  final double lat, lng;
  final DateTime date;

  @override
  State<ArSkyScreen> createState() => _ArSkyScreenState();
}

class _ArSkyScreenState extends State<ArSkyScreen> {
  CameraController? _camera;
  String? _cameraError;
  StreamSubscription<AccelerometerEvent>? _accSub;
  StreamSubscription<MagnetometerEvent>? _magSub;
  Vec3? _gravity, _magnetic;
  DeviceAttitude? _orientation;
  double _headingOffset = 0;
  double _vfov = 62; // dikey görüş açısı (dikey tutuşta), kalibre edilebilir
  late final NightPlan _plan = planNight(widget.date, widget.lat, widget.lng);
  late final List<Sample> _nightPath = _pathSamples();
  DateTime _time = DateTime.now();
  Timer? _clock;
  final Set<String> _layers = {'mw', 'moon'}; // mw | moon | sun | grid

  List<Sample> _pathSamples() {
    // Gece boyunca (gün batımı → gün doğumu) 15 dakikada bir
    final start = _plan.sunset?.millisecondsSinceEpoch ?? _plan.samples.first.t;
    final end = _plan.sunrise?.millisecondsSinceEpoch ?? _plan.samples.last.t;
    return [
      for (final s in _plan.samples)
        if (s.t >= start &&
            s.t <= end &&
            (s.t - start) % (15 * 60000) < 5 * 60000)
          s,
    ];
  }

  @override
  void initState() {
    super.initState();
    // Tanıtım (ilk açılışta) kamera izni penceresinden önce gösterilir
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) await Intros.maybeShow(context, 'night_ar');
      if (mounted) _initCamera();
    });
    _accSub =
        accelerometerEventStream(samplingPeriod: SensorInterval.gameInterval)
            .listen((e) {
              _gravity = lowPass(_gravity, Vec3(e.x, e.y, e.z));
              _update();
            });
    _magSub =
        magnetometerEventStream(samplingPeriod: SensorInterval.gameInterval)
            .listen((e) {
              _magnetic = lowPass(_magnetic, Vec3(e.x, e.y, e.z), 0.1);
              _update();
            });
    // Planlanan gece bugün değilse çekirdeğin doruk anını göster
    final today = DateTime.now();
    if (!DateUtils.isSameDay(widget.date, today) && nightCoreHighest(_plan) != null) {
      _time = nightCoreHighest(_plan)!.t;
    }
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (DateUtils.isSameDay(widget.date, DateTime.now())) {
        setState(() => _time = DateTime.now());
      }
    });
  }

  Future<void> _initCamera() async {
    try {
      final cams = await availableCameras();
      final back = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cams.first,
      );
      final ctrl = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await ctrl.initialize();
      if (!mounted) {
        await ctrl.dispose();
        return;
      }
      setState(() => _camera = ctrl);
    } catch (e) {
      if (mounted) setState(() => _cameraError = '$e');
    }
  }

  void _update() {
    final g = _gravity, m = _magnetic;
    if (g == null || m == null) return;
    final o = orientationFrom(g, m, headingOffset: _headingOffset);
    if (o != null && mounted) setState(() => _orientation = o);
  }

  /// Ay ekranın ortasındayken dokunulur: pusula sapmasını Ay'ın hesaplanan azimutuna göre düzeltir.
  void _alignToMoon() {
    final o = _orientation;
    if (o == null) return;
    final moon = moonPosition(
      _time.millisecondsSinceEpoch,
      widget.lat,
      widget.lng,
    );
    if (moon.alt < 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(L10n.of(context)('ar.moon_down'))));
      return;
    }
    setState(
      () => _headingOffset =
          ((_headingOffset + moon.az - o.pointing.az + 540) % 360) - 180,
    );
    _update();
  }

  /// Pusula ve görüş açısı ayarı (alt sayfa).
  void _calibrationSheet() {
    final t = L10n.of(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(t('ar.calibrate'), style: font(19, weight: 700)),
                const SizedBox(height: 6),
                Text(t('ar.hint'), style: font(13.5, height: 1.4)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(t('ar.fov')),
                    Expanded(
                      child: Slider(
                        value: _vfov,
                        min: 35,
                        max: 90,
                        onChanged: (v) {
                          set(() {});
                          setState(() => _vfov = v);
                        },
                      ),
                    ),
                    Text('${_vfov.round()}°'),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          Navigator.pop(c);
                          _alignToMoon();
                        },
                        child: Text(t('ar.align_moon')),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () {
                        setState(() => _headingOffset = 0);
                        _update();
                        Navigator.pop(c);
                      },
                      child: Text(t('ar.reset')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _accSub?.cancel();
    _magSub?.cancel();
    _clock?.cancel();
    _camera?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    final locale = t.locale.languageCode;
    final o = _orientation;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_camera != null && _camera!.value.isInitialized)
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _camera!.value.previewSize!.height,
                height: _camera!.value.previewSize!.width,
                child: CameraPreview(_camera!),
              ),
            )
          else
            Center(
              child: Text(
                _cameraError == null ? '' : t('ar.camera_error'),
                style: font(14, color: Colors.white70),
                textAlign: TextAlign.center,
              ),
            ),
          if (o != null)
            CustomPaint(
              painter: _SkyOverlay(
                o,
                _nightPath,
                _time,
                widget.lat,
                widget.lng,
                _vfov,
                locale,
                p.accent,
                _layers,
              ),
            )
          else
            Center(
              child: Text(
                t('ar.waiting'),
                style: font(15, color: Colors.white),
              ),
            ),
          // Üst çubuk: başlık, yön, Ay durumu ve katmanlar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ArGlassButton(
                        icon: LucideIcons.chevronLeft,
                        label: t('ui.back'),
                        onTap: () => Navigator.of(context).maybePop(),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ArGlass(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(text: 'Night AR', style: font(13.5, weight: 700, color: Colors.white)),
                                TextSpan(
                                  text: o == null
                                      ? ''
                                      : ' · ${compassPoint(o.pointing.az, locale)} ${o.pointing.az.round()}° · ${o.pointing.alt.round()}°',
                                  style: font(13.5, color: Colors.white70),
                                ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ArGlass(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            MoonGlyph(
                              phase: _plan.phase,
                              fraction: _plan.illumination,
                              size: 16,
                              dark: const Color(0xFF333A55),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '%${(_plan.illumination * 100).round()}',
                              style: font(13, weight: 600, color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final (k, label) in [
                        ('mw', t('ar.layer_mw')),
                        ('moon', t('ar.layer_moon')),
                        ('sun', t('ar.layer_sun')),
                        ('grid', t('ar.layer_grid')),
                      ])
                        Semantics(
                          button: true,
                          toggled: _layers.contains(k),
                          child: GestureDetector(
                            onTap: () => setState(() => _layers.contains(k) ? _layers.remove(k) : _layers.add(k)),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                              decoration: BoxDecoration(
                                color: _layers.contains(k) ? p.accent : Colors.black.withValues(alpha: 0.45),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(label, style: font(12.5, weight: 700, color: Colors.white)),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // Sağ: kalibrasyon
          Positioned(
            right: 16,
            bottom: 210 + MediaQuery.paddingOf(context).bottom,
            child: Column(
              children: [
                // Bu geceyi (ya da seçili anı) çekim planına kaydet
                ArGlassButton(
                  icon: LucideIcons.calendarPlus,
                  label: t('plan.plan_this'),
                  onTap: () => context.push(Uri(path: '/sky/plans/new', queryParameters: {
                    'kind': 'milkyway',
                    'lat': '${widget.lat}',
                    'lng': '${widget.lng}',
                    'date': '${widget.date.millisecondsSinceEpoch}',
                    if (_time.isAfter(DateTime.now().add(const Duration(minutes: 5))))
                      'at': '${_time.millisecondsSinceEpoch}',
                  }).toString()),
                ),
                const SizedBox(height: 8),
                ArGlassButton(icon: LucideIcons.moon, label: t('ar.align_moon'), onTap: _alignToMoon),
                const SizedBox(height: 8),
                IntroGate(
                  module: 'night_ar',
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ArGlassButton(
                        icon: LucideIcons.circleQuestionMark,
                        label: t('intro.how_it_works'),
                        onTap: () => Intros.show(context, 'night_ar'),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
                ArGlassButton(icon: LucideIcons.slidersHorizontal, label: t('ar.calibrate'), onTap: _calibrationSheet),
              ],
            ),
          ),
          // Alt panel: zaman ve çekim penceresi
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              margin: EdgeInsets.fromLTRB(12, 0, 12, 12 + MediaQuery.paddingOf(context).bottom),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              decoration: BoxDecoration(
                color: const Color(0xD90C0E1C),
                borderRadius: BorderRadius.circular(24),
              ),
              child: ArTimePanel(
                plan: _plan,
                time: _time,
                locale: locale,
                onChanged: (v) => setState(() => _time = v),
                onNow: () => setState(() => _time = DateTime.now()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SkyOverlay extends CustomPainter {
  _SkyOverlay(
    this.o,
    this.path,
    this.time,
    this.lat,
    this.lng,
    this.vfov,
    this.locale,
    this.accent,
    this.layers,
  );
  final Set<String> layers;
  final DeviceAttitude o;
  final List<Sample> path;
  final DateTime time;
  final double lat, lng, vfov;
  final String locale;
  final Color accent;

  void _label(
    Canvas c,
    Offset at,
    String text,
    Color color, {
    double size = 12,
    bool bold = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: font(
          size,
          weight: bold ? 600 : 400,
          color: color,
        ).copyWith(shadows: const [Shadow(blurRadius: 4, color: Colors.black)]),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, at - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    Offset? pt(double az, double alt) {
      final r = project(o, az, alt, size.width, size.height, vfov);
      return r == null ? null : Offset(r.x, r.y);
    }

    // Ufuk çizgisi ve pusula işaretleri
    final horizon = Path();
    var started = false;
    for (var az = 0.0; az <= 360; az += 2) {
      final q = pt(az, 0);
      if (q == null) {
        started = false;
        continue;
      }
      if (!started) {
        horizon.moveTo(q.dx, q.dy);
        started = true;
      } else {
        horizon.lineTo(q.dx, q.dy);
      }
    }
    canvas.drawPath(
      horizon,
      Paint()
        ..color = Colors.white54
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );
    for (var az = 0; az < 360; az += 15) {
      final q = pt(az.toDouble(), 0);
      if (q == null) continue;
      final major = az % 90 == 0;
      canvas.drawLine(
        q,
        q + Offset(0, major ? 14 : 7),
        Paint()
          ..color = Colors.white70
          ..strokeWidth = major ? 2 : 1,
      );
      if (az % 45 == 0) {
        _label(
          canvas,
          q + const Offset(0, 26),
          compassPoint(az.toDouble(), locale),
          Colors.white,
          bold: major,
          size: major ? 15 : 12,
        );
      }
    }

    final ms0 = time.millisecondsSinceEpoch;

    Path curve(Iterable<AltAz> points, double minAlt) {
      final path = Path();
      var open = false;
      for (final a in points) {
        final q = a.alt > minAlt ? pt(a.az, a.alt) : null;
        if (q == null) {
          open = false;
          continue;
        }
        if (open) {
          path.lineTo(q.dx, q.dy);
        } else {
          path.moveTo(q.dx, q.dy);
        }
        open = true;
      }
      return path;
    }

    // Yükseklik / azimut ızgarası
    if (layers.contains('grid')) {
      final g = Paint()
        ..color = Colors.white24
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke;
      for (final alt in [15.0, 30.0, 45.0, 60.0, 75.0]) {
        canvas.drawPath(curve([for (var az = 0.0; az <= 360; az += 3) AltAz(az, alt)], -1), g);
        final lq = pt(o.pointing.az, alt);
        if (lq != null) _label(canvas, lq + const Offset(18, -8), '${alt.round()}°', Colors.white60, size: 10);
      }
      for (var az = 0.0; az < 360; az += 30) {
        canvas.drawPath(curve([for (var alt = 0.0; alt <= 88; alt += 3) AltAz(az, alt)], -1), g);
      }
    }

    // Samanyolu bandı: galaktik düzlem (b = 0) ve kenarları (b = ±10°)
    if (layers.contains('mw')) {
      Path band(double b) => curve(galacticBand(ms0, lat, lng, b: b, stepDeg: 3).map((e) => e.pos), -8);
      final degPx = size.height / vfov;
      canvas.drawPath(
        band(0),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 16 * degPx
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFFB8A8FF).withValues(alpha: 0.18)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 * degPx),
      );
      final edge = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFFCFC4FF).withValues(alpha: 0.35);
      canvas.drawPath(band(10), edge);
      canvas.drawPath(band(-10), edge);
    }

    // Güneşin gündüz yolu ve şu anki yeri
    if (layers.contains('sun')) {
      final day = DateTime.fromMillisecondsSinceEpoch(ms0);
      final base = DateTime(day.year, day.month, day.day).millisecondsSinceEpoch;
      final pts = [for (var m = 0; m <= 24 * 60; m += 10) sunPosition(base + m * 60000, lat, lng)];
      canvas.drawPath(
        curve(pts, -10),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xFFFFB35A).withValues(alpha: 0.8),
      );
      for (var h = 0; h < 24; h += 2) {
        final sp = pts[h * 6];
        final q = sp.alt > -2 ? pt(sp.az, sp.alt) : null;
        if (q != null) _label(canvas, q + const Offset(0, -12), '$h', const Color(0xFFFFCF6B), size: 10);
      }
      final sp = sunPosition(ms0, lat, lng);
      final sq = pt(sp.az, sp.alt);
      if (sq != null) {
        canvas.drawCircle(sq, 12, Paint()..color = const Color(0xFFFFD27A));
        _label(canvas, sq + const Offset(0, 24), locale == 'tr' ? 'Güneş' : 'Sun', Colors.white, bold: true);
      }
    }

    // Gece boyunca çekirdeğin ve Ay'ın yolu (saat etiketleriyle)
    void track(AltAz Function(Sample) get, Color color, double width) {
      final pathLine = Path();
      var open = false;
      for (final s in path) {
        final pos = get(s);
        final q = pos.alt > -5 ? pt(pos.az, pos.alt) : null;
        if (q == null) {
          open = false;
          continue;
        }
        if (!open) {
          pathLine.moveTo(q.dx, q.dy);
          open = true;
        } else {
          pathLine.lineTo(q.dx, q.dy);
        }
        final d = DateTime.fromMillisecondsSinceEpoch(s.t);
        if (d.minute < 5) {
          canvas.drawCircle(q, 3, Paint()..color = color);
          _label(
            canvas,
            q + const Offset(0, -14),
            DateFormat.H(locale).format(d),
            color,
            size: 11,
          );
        }
      }
      canvas.drawPath(
        pathLine,
        Paint()
          ..color = color.withValues(alpha: 0.85)
          ..strokeWidth = width
          ..style = PaintingStyle.stroke,
      );
    }

    if (layers.contains('mw')) track((s) => s.core, const Color(0xFFFFCF6B), 2.5);
    if (layers.contains('moon')) track((s) => s.moon, Colors.white70, 2);

    // Şu anki (ya da seçilen) konumlar
    final ms = time.millisecondsSinceEpoch;
    final core = corePosition(ms, lat, lng), moon = moonPosition(ms, lat, lng);
    final cq = layers.contains('mw') ? pt(core.az, core.alt) : null;
    if (cq != null) {
      // Çekirdek, Samanyolu bandının en parlak bölgesi: yumuşak bir hale ile göster
      canvas.drawCircle(
        cq,
        26,
        Paint()
          ..shader = RadialGradient(
            colors: [
              accent.withValues(alpha: 0.55),
              accent.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: cq, radius: 26)),
      );
      canvas.drawCircle(cq, 6, Paint()..color = accent);
      _label(
        canvas,
        cq + const Offset(0, 22),
        '${locale == 'tr' ? 'Galaktik çekirdek' : 'Galactic core'} · ${core.alt.round()}°',
        Colors.white,
        bold: true,
      );
    }
    final mq = layers.contains('moon') ? pt(moon.az, moon.alt) : null;
    if (mq != null) {
      canvas.drawCircle(mq, 11, Paint()..color = Colors.white);
      _label(
        canvas,
        mq + const Offset(0, 22),
        locale == 'tr' ? 'Ay' : 'Moon',
        Colors.white,
        bold: true,
      );
    }

    // Ekran ortası nişangâhı (Ay'a hizalama için)
    final c = Offset(size.width / 2, size.height / 2);
    final cross = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.2;
    canvas.drawCircle(c, 14, cross..style = PaintingStyle.stroke);
    canvas.drawLine(c - const Offset(22, 0), c - const Offset(16, 0), cross);
    canvas.drawLine(c + const Offset(16, 0), c + const Offset(22, 0), cross);
  }

  @override
  bool shouldRepaint(covariant _SkyOverlay old) => true;
}
