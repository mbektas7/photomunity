/// Derleme anında verilir:
/// flutter run --dart-define=API_URL=http://10.0.2.2:8000/api/v1 --dart-define=GOOGLE_SERVER_CLIENT_ID=...
class AppConfig {
  static const apiUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://localhost:8000/api/v1',
  );

  /// Gerçek zamanlı mesajlar. Verilmezse API adresinden türetilir (http→ws, sonuna /ws).
  static const _wsUrl = String.fromEnvironment('WS_URL');
  static String get wsUrl => _wsUrl.isNotEmpty
      ? _wsUrl
      : '${apiUrl.replaceFirst(RegExp('^http'), 'ws')}/ws';

  /// Harita altlığı (raster). Varsayılan CARTO; üretimde anahtarlı bir sağlayıcı (MapTiler, Stadia) önerilir.
  static const mapTilesLight = String.fromEnvironment(
    'MAP_TILES_LIGHT',
    defaultValue:
        'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
  );
  static const mapTilesDark = String.fromEnvironment(
    'MAP_TILES_DARK',
    defaultValue:
        'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
  );
  static const mapAttribution = String.fromEnvironment(
    'MAP_ATTRIBUTION',
    defaultValue: '© OpenStreetMap katkıcıları © CARTO',
  );

  /// AdMob reklam birimleri. Varsayılanlar Google'ın resmi TEST birimleridir; yayından önce gerçekleriyle değiştirin.
  static const admobBannerAndroid = String.fromEnvironment(
    'ADMOB_BANNER_ANDROID',
    defaultValue: 'ca-app-pub-3940256099942544/6300978111',
  );
  static const admobBannerIos = String.fromEnvironment(
    'ADMOB_BANNER_IOS',
    defaultValue: 'ca-app-pub-3940256099942544/2934735716',
  );

  /// RevenueCat herkese açık SDK anahtarları (platform başına).
  static const revenueCatIos = String.fromEnvironment('RC_IOS_KEY');
  static const revenueCatAndroid = String.fromEnvironment('RC_ANDROID_KEY');

  /// Yönetim ekranları (yarışma kurma, jüri, topluluk ayarları) web'de açılır.
  static const webUrl = String.fromEnvironment(
    'WEB_URL',
    defaultValue: 'http://localhost:3000',
  );

  /// Google'ın id_token'ı backend için imzalaması için web (server) client id. Backend'in GOOGLE_CLIENT_IDS listesinde olmalı.
  static const googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
  );

  /// iOS için ayrı client id (Android'de gerekmez).
  static const googleIosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
  );

  // Backend varsayılanlarıyla aynı; kesin kontrol sunucudadır.
  static const minBytes = 1000000;
  static const maxBytes = 40000000;
  static const minLongEdge = 2000;
}
