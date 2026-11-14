import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/l10n.dart';
import 'core/theme.dart';
import 'router.dart';
import 'state/providers.dart';

class FotografyaApp extends ConsumerWidget {
  const FotografyaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    ref.watch(
      realtimeProvider,
    ); // oturum açıkken WebSocket bağlantısını canlı tutar
    ref.watch(purchasesProvider); // RevenueCat kullanıcısını oturumla eşler
    ref.listen(authProvider, (_, next) {
      final me = next.asData?.value;
      if (me != null && !me.isPro)
        ref
            .read(adsProvider)
            .start(); // izin formu + AdMob, yalnızca reklam görecekler için
    });
    ref.listen(authProvider, (prev, next) {
      final wasIn = prev?.asData?.value != null;
      final isIn = next.asData?.value != null;
      if (isIn && !wasIn) ref.read(pushProvider).enable();
    });
    ref.listen(pendingRouteProvider, (_, route) {
      if (route == null) return;
      ref.read(pendingRouteProvider.notifier).clear();
      if (ref.read(authProvider).asData?.value != null) router.push(route);
    });
    return MaterialApp.router(
      title: 'Fotografya',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      locale: ref.watch(localeProvider),
      supportedLocales: L10n.supported,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: router,
    );
  }
}
