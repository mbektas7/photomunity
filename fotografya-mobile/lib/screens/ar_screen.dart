import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:sensors_plus/sensors_plus.dart';

import '../core/ar_math.dart';
import '../core/astro.dart';
import '../core/l10n.dart';
import '../core/theme.dart';

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
    _initCamera();
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
    if (!DateUtils.isSameDay(widget.date, today) && _plan.coreTransit != null)
      _time = _plan.coreTransit!.t;
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (DateUtils.isSameDay(widget.date, DateTime.now()))
        setState(() => _time = DateTime.now());
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
              ),
            )
          else
            Center(
              child: Text(
                t('ar.waiting'),
                style: font(15, color: Colors.white),
              ),
            ),
          // Üst çubuk
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(LucideIcons.x, color: Colors.white),
                  ),
                  Expanded(
                    child: Text(
                      o == null
                          ? ''
                          : '${compassPoint(o.pointing.az, locale)} ${o.pointing.az.round()}° · ${o.pointing.alt.round()}°',
                      style: font(15, weight: 600, color: Colors.white),
                    ),
                  ),
                  Text(
                    DateFormat.Hm(locale).format(_time),
                    style: font(15, weight: 600, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
          // Alt panel: kalibrasyon
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              color: Colors.black.withValues(alpha: 0.6),
              padding: EdgeInsets.fromLTRB(
                16,
                12,
                16,
                12 + MediaQuery.paddingOf(context).bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    t('ar.hint'),
                    style: font(12.5, height: 1.4, color: Colors.white70),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor: Colors.transparent,
                            side: const BorderSide(color: Colors.white54),
                          ),
                          onPressed: _alignToMoon,
                          child: Text(t('ar.align_moon')),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white70,
                        ),
                        onPressed: () => setState(() {
                          _headingOffset = 0;
                          _update();
                        }),
                        child: Text(t('ar.reset')),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Text(
                        t('ar.fov'),
                        style: font(12.5, color: Colors.white70),
                      ),
                      Expanded(
                        child: Slider(
                          value: _vfov,
                          min: 35,
                          max: 90,
                          onChanged: (v) => setState(() => _vfov = v),
                        ),
                      ),
                      Text(
                        '${_vfov.round()}°',
                        style: font(12.5, color: Colors.white70),
                      ),
                    ],
                  ),
                  Slider(
                    value: _time.millisecondsSinceEpoch.toDouble().clamp(
                      _plan.samples.first.t.toDouble(),
                      _plan.samples.last.t.toDouble(),
                    ),
                    min: _plan.samples.first.t.toDouble(),
                    max: _plan.samples.last.t.toDouble(),
                    onChanged: (v) => setState(
                      () => _time = DateTime.fromMillisecondsSinceEpoch(
                        v.round(),
                      ),
                    ),
                  ),
                ],
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
  );
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
      if (az % 45 == 0)
        _label(
          canvas,
          q + const Offset(0, 26),
          compassPoint(az.toDouble(), locale),
          Colors.white,
          bold: major,
          size: major ? 15 : 12,
        );
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

    track((s) => s.core, accent, 3);
    track((s) => s.moon, Colors.white70, 2);

    // Şu anki (ya da seçilen) konumlar
    final ms = time.millisecondsSinceEpoch;
    final core = corePosition(ms, lat, lng), moon = moonPosition(ms, lat, lng);
    final cq = pt(core.az, core.alt);
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
        locale == 'tr' ? 'Samanyolu çekirdeği' : 'Milky Way core',
        Colors.white,
        bold: true,
      );
    }
    final mq = pt(moon.az, moon.alt);
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
