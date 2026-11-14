# Fotografya Mobil — Faz 1

Flutter (iOS + Android), Riverpod 3, go_router, Dio. Web ile aynı backend, aynı tasarım dili.

> **Önemli:** Bu kod Flutter SDK'sı olmayan bir ortamda yazıldı. Sözdizimi `dart format` ile, veri modelleri ise backend'in gerçek JSON yanıtlarıyla `dart analyze` ve çalıştırılarak doğrulandı. Flutter widget katmanı henüz derlenmedi; ilk adım olarak `flutter analyze` çalıştırın. Çıkacak hatalar büyük olasılıkla paket sürümlerindeki küçük API farkları olacaktır.

## Kurulum

```bash
# 1) Platform klasörlerini oluştur (mevcut lib/ ve pubspec.yaml'a dokunmaz)
flutter create . --org app.fotografya --project-name fotografya --platforms=android,ios

# 2) Paketler ve analiz
flutter pub get
flutter analyze

# 3) Çalıştır (Android emülatöründen bilgisayardaki API'ye 10.0.2.2 ile erişilir)
flutter run \
  --dart-define=API_URL=http://10.0.2.2:8000/api/v1 \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=xxxx.apps.googleusercontent.com \
  --dart-define=GOOGLE_IOS_CLIENT_ID=yyyy.apps.googleusercontent.com
```

Gereksinim: Flutter 3.35+ (Dart 3.9+). Kod null-aware koleksiyon elemanları (`?değer`) ve `DropdownButtonFormField.initialValue` kullanır.

## Platform ayarları

`flutter create` sonrası aşağıdakileri ekleyin.

**iOS — `ios/Runner/Info.plist`**

```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>Paylaşmak istediğin fotoğrafı seçebilmen için.</string>
<key>NSLocationWhenInUseUsageDescription</key>
<string>Fotoğrafına ve profiline isteğe bağlı konum ekleyebilmen için.</string>
<!-- Google ile giriş: iOS client id'nin ters çevrilmiş hali -->
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array><string>com.googleusercontent.apps.yyyy</string></array>
  </dict>
</array>
```

Xcode'da Runner hedefine **Sign in with Apple** yeteneğini ekleyin. Minimum iOS sürümü 14 olmalı.

**Android — `android/app/src/main/AndroidManifest.xml`**

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<!-- Seçilen fotoğrafın EXIF GPS bilgisinin silinmemesi için -->
<uses-permission android:name="android.permission.ACCESS_MEDIA_LOCATION" />
```

Yerel geliştirmede HTTP için `android/app/src/debug/AndroidManifest.xml` içindeki `<application>` etiketine `android:usesCleartextTraffic="true"` ekleyin. `minSdk` en az 23 olmalı (`flutter_secure_storage`).

Google ile giriş için Google Cloud Console'da Android OAuth istemcisi oluşturup debug/release SHA-1 parmak izlerini ekleyin. `GOOGLE_SERVER_CLIENT_ID` web istemcisinin id'sidir. Bu id ve iOS id'si backend'deki `GOOGLE_CLIENT_IDS` listesinde olmalı. Apple için iOS bundle id'si (`app.fotografya.fotografya`) backend'in `APPLE_CLIENT_IDS` listesine eklenmeli.

## Yapı

```
lib/
  core/      config, api_client (token + tek seferlik yenileme), token_store (Keychain/Keystore),
             models, theme (web ile aynı renk token'ları), l10n (TR/EN)
  state/     providers: oturum, sayfalı listeler, detaylar, iyimser beğeniler
  widgets/   justified_wall, viewfinder, photo_widgets, common
  screens/   auth, feed, explore, photo, profile, upload, settings
  router.dart  oturuma göre yönlendirme + alt sekmeler (Akış, Keşfet, Yükle, Profil)
```

## Web ile aynı kalan kararlar

- **Kırpılmayan duvar.** Keşfet, profil ve karşılama ekranındaki duvar, web'deki algoritmanın aynısıdır.
- **Siyah vizör şeridi.** EXIF, temadan bağımsız siyah bir şeritte gösterilir.
- **Token güvenliği.** Token'lar Keychain/Keystore'da tutulur. Aynı anda gelen 401'ler tek bir yenilemeyi bekler; aksi halde backend'in çalıntı-token koruması tüm oturumları kapatır.
- **EXIF'in korunması.** Yüklemede `image_picker` sıkıştırma parametresi almaz; aksi halde fotoğraf yeniden sıkıştırılır ve EXIF kaybolur.
- **Ön kontrol.** Boyut ve çözünürlük, görsel tamamen açılmadan cihazda kontrol edilir; kesin karar sunucudadır.

## Bilinen sınırlar

- E-posta doğrulama ve şifre sıfırlama bağlantıları web'de açılır. Uygulama içi deep link, Universal Links / App Links kurulunca eklenecek.
- iOS fotoğraf seçici bazı HEIC dosyalarını JPEG'e çevirebilir. EXIF korunur, ama dosya boyutu değişebilir.

## Push bildirimleri (Firebase)

```bash
dart pub global activate flutterfire_cli
flutterfire configure --project=<firebase-proje-id> --platforms=android,ios
```

Bu komut `google-services.json` ve `GoogleService-Info.plist` dosyalarını yerleştirir. Uygulama `Firebase.initializeApp()`'i seçeneksiz çağırır ve yerel yapılandırmayı kullanır; dosyalar yoksa push sessizce devre dışı kalır, uygulamanın geri kalanı çalışır.

- iOS: Xcode'da **Push Notifications** ve **Background Modes → Remote notifications** yeteneklerini açın, APNs anahtarını Firebase konsoluna yükleyin.
- Android 13+: bildirim izni uygulama içinde istenir (`firebase_messaging` `POST_NOTIFICATIONS` iznini ekler).
- Backend tarafında aynı Firebase projesinin servis hesabı `FCM_SERVICE_ACCOUNT_FILE` ile verilmelidir.

Oturum açılınca cihaz token'ı `POST /devices` ile kaydedilir, çıkışta silinir. Bildirime dokunulunca ilgili fotoğraf, profil, topluluk ya da yarışma açılır.

## Faz 2: Topluluklar ve yarışmalar

Alt sekmede **Topluluklar**: topluluk arama, katılma, topluluk açma; topluluk sayfasında akış (fotoğraf paylaşımı, yöneticiler için haber), yarışmalar ve üyeler. Aynı sekmede **Yarışmalar**: katılıma açık, oylamada ve sonuçlanan yarışmalar.

Yarışma ekranı döneme göre değişir: katılım (kendi fotoğrafından seçerek katılma ve geri çekme), halk oylaması (yıldız verme, kendi karesinde "Senin karen"), jüri dönemi (jüri üyesi için puanlama ekranı), sonuç (kürsü ve sıralama). Jüri ekranı tam ekran ve anonimdir: kaydırarak gezilir, puan verince sıradaki puanlanmamış kareye geçer.

**Bilinçli sınır:** Yarışma kurma, jüri atama ve ağırlıklar, yayınlama, katılım geçersiz sayma ve topluluk ayarları uzun formlar gerektirdiği için mobilde "Webde yönet" düğmesiyle web paneline açılır. Web adresi `--dart-define=WEB_URL=https://fotografya.app` ile verilir.

## Faz 3: Harita ve mesajlar

- **Harita** (`flutter_map`): Keşfet ekranındaki "Harita" düğmesinden açılır. Fotoğrafçılar ve fotoğraflar katmanları, uzmanlık filtresi, sunucuda kümelenmiş işaretçiler, profil/mesaj kartı. Fotoğraf detayındaki konum da bu haritada açılır. Altlık varsayılan olarak CARTO raster karolarıdır; üretimde anahtarlı bir sağlayıcı önerilir: `--dart-define=MAP_TILES_LIGHT=... --dart-define=MAP_TILES_DARK=... --dart-define=MAP_ATTRIBUTION=...`
- **Mesajlar:** Akış ekranının üst çubuğundaki sohbet simgesinden (okunmamış rozetli). Gelen kutusu ve istekler, sohbet ekranı (fotoğraf ve konum paylaşımı, görüldü, kabul/ret, engelleme). Profilde ve harita kartında "Mesaj gönder".
- **Gerçek zamanlı:** Oturum açıkken `WS_URL` adresine (verilmezse `API_URL`'den türetilir) WebSocket ile bağlanır. Her bağlantıdan önce yetkili bir istekle erişim token'ı tazelenir; koparsa artan aralıklarla yeniden bağlanır. Mesaj bildirimine dokununca ilgili sohbet açılır.

## Rehber, hesaplayıcılar ve gökyüzü planlayıcı

Keşfet ekranındaki kitap simgesinden açılır: senaryoya göre ayar rehberi, hesaplayıcılar ve gece planlayıcısı. Hesaplar (`lib/core/astro.dart`, `lib/core/calculators.dart`) web ile birebir aynıdır ve cihazda yapılır; internet gerekmez.

**AR görünümü** (planlayıcıdaki "AR ile gökyüzüne bak"): kamera görüntüsü üzerinde ufuk çizgisi, pusula yönleri, Samanyolu çekirdeğinin ve Ay'ın bu gecelik yolu (saat etiketleriyle) ve anlık konumları. Yönelim ivmeölçer ve manyetometreden hesaplanır (`lib/core/ar_math.dart`; dört ana yön, eğim, yatay tutuş ve kalibrasyon testlerle doğrulandı). Telefon pusulası birkaç derece sapabilir ve manyetik sapma konuma göre değişir; bu yüzden iki kalibrasyon var: Ay görünürken onu ortadaki halkaya getirip "Ay'a hizala"ya dokunmak, ve kamera görüş açısı kaydırıcısı.

İzinler — iOS `Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>Gökyüzü planlayıcıda Samanyolu ve Ay'ın yolunu kamera görüntüsü üzerinde göstermek için.</string>
```

Android `AndroidManifest.xml`: `<uses-permission android:name="android.permission.CAMERA" />`

**Cihazda doğrulanması gerekenler:** AR katmanı gerçek bir telefonda henüz denenmedi. `sensors_plus` iOS değerlerini Android sözleşmesine çevirir; yine de ilk denemede telefon kuzeye ve ufka tutulduğunda üst çubuğun yaklaşık "K 0° · 0°" gösterdiğini kontrol edin. Ters bir eksen görürseniz `ar_math.dart` içindeki `orientationFrom` girişinde yerçekimi vektörünün işaretinin çevrilmesi yeterlidir.

## Reklamlar ve Pro (Faz 4)

**Reklamlar (AdMob):** Akışta her 8 gönderide bir ve rehberin altında 300×250 reklam. Fotoğraf detayı, mesajlar, AR ve yarışma oylaması reklamsızdır; Pro kullanıcılar hiç reklam görmez. Reklamlar başlamadan önce Google'ın izin formu (UMP) gösterilir; izin yoksa AdMob başlatılmaz. Varsayılan reklam birimleri Google'ın **test** birimleridir; yayından önce `--dart-define=ADMOB_BANNER_ANDROID=... --dart-define=ADMOB_BANNER_IOS=...` verin.

- iOS `Info.plist`: `GADApplicationIdentifier` (AdMob uygulama kimliği), AdMob belgesindeki `SKAdNetworkItems` listesi ve kişiselleştirilmiş reklam için `NSUserTrackingUsageDescription`. AdMob panelinde *Gizlilik ve mesajlaşma* altında GDPR ve iOS ATT mesajlarını açın.
- Android `AndroidManifest.xml` `<application>` içine:
  `<meta-data android:name="com.google.android.gms.ads.APPLICATION_ID" android:value="ca-app-pub-XXXX~YYYY"/>`

**Pro (RevenueCat):**

1. App Store Connect ve Google Play Console'da iki otomatik yenilenen abonelik oluşturun, ör. `fotografya_pro_monthly` ($1.99) ve `fotografya_pro_yearly` ($17.99). Türkiye için mağazanın yerel fiyat katmanını ayrıca belirleyin.
2. RevenueCat'te `pro` adlı bir yetki (entitlement) ve iki paketi içeren bir *current offering* tanımlayın.
3. RevenueCat webhook'unu backend'e yönlendirin (API README'sindeki adres ve Authorization başlığı).
4. Uygulamayı anahtarlarla çalıştırın: `--dart-define=RC_IOS_KEY=appl_... --dart-define=RC_ANDROID_KEY=goog_...`

Satın alma sonrası uygulama backend'i hemen eşitler (`/billing/sync`), böylece Pro webhook'u beklemeden açılır. Fiyatlar mağazadan, kullanıcının para biriminde gelir.

**Mağaza kuralları:** Ekranda "Satın almaları geri yükle" düğmesi ve otomatik yenileme açıklaması var. Yayından önce Pro ekranına kullanıcı sözleşmesi ve gizlilik politikası bağlantılarını ekleyin; Apple bunları abonelik ekranında zorunlu tutar. iOS uygulamasında web ödemesine yönlendirme yapılmaz.
