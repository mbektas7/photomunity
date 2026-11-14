// Tasarım doğrulaması için ekran görüntüsü üretir (cihaz/emülatör gerekmez).
//
// Yerel API ve demo hesabıyla çalışır; normal `flutter test` çalıştırmasında atlanır:
//   flutter test test/design_render_test.dart \
//     --dart-define=RENDER_OUT=/tmp/shots \
//     --dart-define=RENDER_LOGIN=email:parola \
//     --dart-define=RENDER_ROUTES=/feed,/explore \
//     --dart-define=RENDER_DARK=false
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotografya/core/config.dart';
import 'package:fotografya/core/l10n.dart';
import 'package:fotografya/core/theme.dart';
import 'package:fotografya/core/token_store.dart';
import 'package:fotografya/router.dart';
import 'package:fotografya/state/providers.dart';
import 'package:fotografya/widgets/common.dart';

const _out = String.fromEnvironment('RENDER_OUT');
const _login = String.fromEnvironment('RENDER_LOGIN');
const _routes = String.fromEnvironment('RENDER_ROUTES', defaultValue: '/feed');
const _dark = bool.fromEnvironment('RENDER_DARK');

class _MemoryTokens extends TokenStore {
  _MemoryTokens(this._t);
  Tokens? _t;
  @override
  Future<Tokens?> read() async => _t;
  @override
  Future<void> save(Tokens t) async => _t = t;
  @override
  Future<void> clear() async => _t = null;
}

Future<void> _loadFont(String family, String path) async {
  final loader = FontLoader(family)
    ..addFont(Future.value(ByteData.sublistView(File(path).readAsBytesSync())));
  await loader.load();
}

String _flutterRoot() =>
    Platform.environment["FLUTTER_ROOT"] ??
    File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.parent.path;

Future<String> _pubPackage(String name) async {
  final cfg = jsonDecode(File('.dart_tool/package_config.json').readAsStringSync()) as Map;
  final pkg = (cfg['packages'] as List).cast<Map>().firstWhere((p) => p['name'] == name);
  return Uri.parse(pkg['rootUri'] as String).toFilePath();
}

void main() {
  testWidgets('tasarım ekranları', (tester) async {
    if (_out.isEmpty || _login.isEmpty) return; // yalnızca açıkça istenince

    final images = <String, Uint8List>{};
    HttpOverrides.global = null; // yerel API'ye gerçek istek

    late Tokens tokens;
    await tester.runAsync(() async {
      await _loadFont('BricolageGrotesque', 'assets/fonts/BricolageGrotesque-Variable.ttf');
      final lucide = await _pubPackage('lucide_icons_flutter');
      await _loadFont('packages/lucide_icons_flutter/Lucide', '$lucide/assets/lucide.ttf');
      await _loadFont('MaterialIcons', '${_flutterRoot()}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');

      final sep = _login.indexOf(':');
      final c = HttpClient();
      final req = await c.postUrl(Uri.parse('${AppConfig.apiUrl}/auth/login'));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({'email': _login.substring(0, sep), 'password': _login.substring(sep + 1)}));
      final res = await req.close();
      final body = jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
      tokens = Tokens.fromJson((body['tokens'] ?? body) as Map<String, dynamic>);
    });

    // Ağ görselleri: önceden indirilip bellekten çizilir.
    debugNetImage = (url, fit) {
      final bytes = images[url];
      if (bytes == null) {
        images[url] = Uint8List(0); // sonraki turda indirilecek
        return const ColoredBox(color: Color(0x11000000));
      }
      if (bytes.isEmpty) return const ColoredBox(color: Color(0x11000000));
      return Image.memory(bytes, fit: fit, gaplessPlayback: true);
    };

    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.platformBrightnessTestValue = _dark ? Brightness.dark : Brightness.light;

    final container = ProviderContainer(overrides: [
      tokenStoreProvider.overrideWithValue(_MemoryTokens(tokens)),
      localeProvider.overrideWithValue(const Locale('tr')),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: Consumer(builder: (context, ref, _) => MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
        locale: const Locale('tr'),
        supportedLocales: L10n.supported,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        routerConfig: ref.watch(routerProvider),
      )),
    ));

    Future<void> settle() async {
      for (var round = 0; round < 6; round++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 700)));
        await tester.pump(const Duration(milliseconds: 100));
        final missing = images.entries.where((e) => e.value.isEmpty).map((e) => e.key).toList();
        if (missing.isNotEmpty) {
          await tester.runAsync(() async {
            final c = HttpClient();
            for (final url in missing) {
              try {
                final r = await (await c.getUrl(Uri.parse(url))).close();
                final b = await r.fold<List<int>>(<int>[], (a, x) => a..addAll(x));
                images[url] = Uint8List.fromList(b.isEmpty ? [0] : b);
              } catch (e) {
                // ignore: avoid_print
                print('fetch fail $url $e');
                images[url] = Uint8List.fromList([0]);
              }
            }
          });
          void dirty(Element e) {
            e.markNeedsBuild();
            e.visitChildren(dirty);
          }
          tester.binding.rootElement?.visitChildren(dirty);
          await tester.pump();
        }
      }
      // Bellekteki görsellerin çözülmesi
      await tester.runAsync(() async {
        for (final el in find.byType(Image).evaluate()) {
          final img = el.widget as Image;
          await precacheImage(img.image, el).catchError((_) {});
        }
      });
      await tester.pump(const Duration(milliseconds: 500));
    }

    final router = container.read(routerProvider);
    Directory(_out).createSync(recursive: true);
    for (final route in _routes.split(',')) {
      final parts = route.split('=');
      router.go(parts[0]);
      await tester.pump();
      await settle();
      await settle();
      final name = parts.length > 1 ? parts[1] : parts[0].replaceAll('/', '_');
      await tester.runAsync(() async {
        final image = await captureImage(tester.element(find.byType(MaterialApp).first));
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        File('$_out/$name-${_dark ? 'dark' : 'light'}.png').writeAsBytesSync(png!.buffer.asUint8List());
      });
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    debugNetImage = null;
  });
}
