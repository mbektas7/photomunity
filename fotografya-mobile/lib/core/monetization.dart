import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import 'config.dart';

/// Reklamlar: önce Google'ın izin formu (GDPR/KVKK için UMP), izin varsa AdMob başlatılır.
class AdsService {
  bool _started = false;
  final ready = ValueNotifier<bool>(false);

  String get bannerUnit =>
      Platform.isIOS ? AppConfig.admobBannerIos : AppConfig.admobBannerAndroid;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    final done = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () =>
          ConsentForm.loadAndShowConsentFormIfRequired((_) => done.complete()),
      (_) => done.complete(), // izin bilgisi alınamazsa yine de dene; SDK kişiselleştirilmemiş reklam gösterir
    );
    await done.future;
    if (!await ConsentInformation.instance.canRequestAds()) return;
    await MobileAds.instance.initialize();
    ready.value = true;
  }
}

/// Mağaza içi satın alma (RevenueCat). Yetki backend'de tutulur; burası yalnızca satın alma akışını yürütür.
class PurchasesService {
  bool _configured = false;

  bool get available =>
      (Platform.isIOS ? AppConfig.revenueCatIos : AppConfig.revenueCatAndroid)
          .isNotEmpty;

  /// Oturum açınca çağrılır: RevenueCat kullanıcısı = backend kullanıcı kimliği (webhook'lar bununla eşleşir).
  Future<void> identify(String userId) async {
    if (!available) return;
    try {
      if (!_configured) {
        await Purchases.configure(
          PurchasesConfiguration(
            Platform.isIOS
                ? AppConfig.revenueCatIos
                : AppConfig.revenueCatAndroid,
          )..appUserID = userId,
        );
        _configured = true;
      } else {
        await Purchases.logIn(userId);
      }
    } catch (e) {
      debugPrint('RevenueCat başlatılamadı: $e');
    }
  }

  Future<void> reset() async {
    if (!_configured) return;
    try {
      await Purchases.logOut();
    } catch (_) {}
  }

  /// Aylık ve yıllık paketler; fiyatlar mağazadan, kullanıcının para biriminde gelir.
  Future<({Package? monthly, Package? annual})> packages() async {
    if (!_configured) return (monthly: null, annual: null);
    final current = (await Purchases.getOfferings()).current;
    return (monthly: current?.monthly, annual: current?.annual);
  }

  /// Satın alır; kullanıcı vazgeçerse false döner.
  Future<bool> buy(Package package) async {
    try {
      await Purchases.purchasePackage(package);
      return true;
    } on PlatformException catch (e) {
      if (PurchasesErrorHelper.getErrorCode(e) ==
          PurchasesErrorCode.purchaseCancelledError) {
        return false;
      }
      rethrow;
    }
  }

  Future<void> restore() async {
    if (_configured) await Purchases.restorePurchases();
  }
}
