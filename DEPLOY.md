# Photomunity — Yayına alma rehberi

Sıra önemlidir: önce alan adı ve altyapı, sonra API, web ve en son mobil uygulamalar.
Her adımın sonunda **Kontrol** satırındaki denemeyi yapın.

Adresler (örnek):

| Adres | Ne |
| --- | --- |
| `https://photomunity.app` | Web |
| `https://api.photomunity.app` | API (FastAPI) |
| `https://cdn.photomunity.app` | Fotoğraflar (yalnızca `photos/` öneki) |

---

## 0. Ön koşullar (hesaplar)

- [ ] Alan adı: `photomunity.app`
- [ ] Kod deposu (GitHub, özel)
- [ ] Apple Developer Program (yıllık ücretli), Google Play Console (tek seferlik ücretli)
- [ ] Firebase, Google Cloud (OAuth), Resend, Stripe, RevenueCat, AdMob, AdSense (isteğe bağlı)

## 1. Altyapı

| Bileşen | Gereksinim | Not |
| --- | --- | --- |
| PostgreSQL 16 | PostGIS eklentisi | Neon, Supabase, Render, RDS |
| Redis 7 | Kalıcı bağlantı | Upstash, Render, ElastiCache |
| Nesne depolama | **Presigned POST desteği** | Tarayıcı ve uygulama dosyayı form POST ile doğrudan yükler. AWS S3 destekler; **Cloudflare R2 desteklemez**. |
| CDN | Bucket'ın `photos/` önekini herkese açar | CloudFront (S3 ile) |
| API + işçi | Docker, iki ayrı süreç | Fly.io, Render, Railway |
| Web | Node.js 20+, **tek örnek** | Aşağıdaki nota bakın |

> **Web neden tek örnek?** Oturum yenileme istekleri sunucu belleğinde birleştiriliyor
> (`photomunity-web/README.md`). Birden fazla örnek ya da sunucusuz (Vercel) dağıtımda eşzamanlı
> yenilemeler API'nin token yeniden kullanım korumasını tetikleyip kullanıcıların oturumunu kapatabilir.
> Başlangıçta web'i tek bir Node süreci olarak (`npm run build && npm start`) çalıştırın; ölçeklemek
> gerektiğinde birleştirme Redis'e taşınmalı.

Depolama ayarları:
- [ ] Bucket: `photomunity`. Herkese açık okuma **yalnızca** `photos/*` için (orijinaller özel kalır).
- [ ] Bucket CORS: `POST` ve `PUT`, köken `https://photomunity.app`.
- [ ] CDN kökeni bucket, yol `photos/*`; adres `CDN_BASE_URL` olacak.

**Kontrol:** `psql` ile bağlanın, `CREATE EXTENSION IF NOT EXISTS postgis;` çalışsın.

## 2. E-posta (Resend)

- [ ] `photomunity.app` alan adını ekleyin, verdiği SPF/DKIM DNS kayıtlarını girin, doğrulanmasını bekleyin.
- [ ] API anahtarı → `RESEND_API_KEY`. Gönderen: `Photomunity <no-reply@photomunity.app>`.

## 3. API ortam değişkenleri

Zorunlu (eksikse API `ENVIRONMENT=production` iken **açılmaz**):

```env
ENVIRONMENT=production
FRONTEND_URL=https://photomunity.app
CORS_ORIGINS=["https://photomunity.app"]
JWT_SECRET=<openssl rand -hex 32>
DATABASE_URL=postgresql+asyncpg://KULLANICI:SIFRE@HOST:5432/photomunity
REDIS_URL=rediss://...
S3_ENDPOINT_URL=            # AWS S3 için boş bırakın
S3_REGION=eu-central-1
S3_ACCESS_KEY=...
S3_SECRET_KEY=...
S3_BUCKET=photomunity
CDN_BASE_URL=https://cdn.photomunity.app
RESEND_API_KEY=re_...
EMAIL_FROM=Photomunity <no-reply@photomunity.app>
TRUST_PROXY_HEADERS=true    # yalnızca güvenilir ters vekil / yük dengeleyici arkasında
```

Özelliklere göre (boşsa ilgili özellik kapalı kalır):

```env
GOOGLE_CLIENT_IDS=["<web>.apps.googleusercontent.com","<ios>...","<android>..."]
APPLE_CLIENT_IDS=["app.photomunity.photomunity","<web Services ID>"]
FCM_SERVICE_ACCOUNT_JSON={...}          # Firebase servis hesabı (push)
STRIPE_SECRET_KEY=sk_live_...
STRIPE_WEBHOOK_SECRET=whsec_...
STRIPE_PRICE_MONTHLY=price_...
STRIPE_PRICE_YEARLY=price_...
REVENUECAT_WEBHOOK_AUTH=<rastgele uzun değer>
REVENUECAT_SECRET_KEY=sk_...
TURNSTILE_SECRET=                       # isteğe bağlı bot doğrulaması
MODERATION_PROVIDER=none                # ya da rekognition (AWS anahtarları gerekir)
```

## 4. API'yi yayınla

`photomunity-api/Dockerfile` ile imaj oluşturun. Aynı imajdan **iki süreç**:

```bash
uvicorn app.main:app --host 0.0.0.0 --port 8000 --proxy-headers   # web süreci
arq app.worker.WorkerSettings                                      # işçi: fotoğraf işleme, yarışma takvimi, abonelik kontrolü
```

Her sürümden önce (yayın komutu olarak):

```bash
alembic upgrade head
```

- [ ] `api.photomunity.app` → API, HTTPS açık; WebSocket (`/api/v1/ws`) destekleniyor olmalı.
- [ ] Demo verisi (`scripts/seed_demo.py`) üretimde **çalıştırılmaz**.

**Kontrol:** `curl https://api.photomunity.app/health` → `{"status":"ok"}`

## 5. Web ortam değişkenleri ve yayın

```env
API_URL=https://api.photomunity.app/api/v1
NEXT_PUBLIC_WS_URL=wss://api.photomunity.app/api/v1/ws
NEXT_PUBLIC_SITE_URL=https://photomunity.app
NEXT_PUBLIC_LEGAL_ENTITY=<şirket unvanı / işleten kişi>
NEXT_PUBLIC_CONTACT_EMAIL=<destek / KVKK başvuru adresi>
NEXT_PUBLIC_GOOGLE_CLIENT_ID=<web>.apps.googleusercontent.com
NEXT_PUBLIC_APPLE_CLIENT_ID=<web Services ID>
NEXT_PUBLIC_APPLE_REDIRECT_URI=https://photomunity.app
NEXT_PUBLIC_APP_STORE_URL=          # uygulamalar yayınlanınca
NEXT_PUBLIC_PLAY_STORE_URL=
APPLE_TEAM_ID=JN5ZA7ZBSC            # Apple hesabınızdaki Team ID ile aynı olmalı
ANDROID_CERT_SHA256=<Play App Signing SHA-256>
NEXT_PUBLIC_ADSENSE_CLIENT=         # isteğe bağlı
```

```bash
npm ci && npm run build && npm start   # PORT ortam değişkeniyle
```

**Kontrol:**
- `https://photomunity.app/tr` açılıyor, kayıt → doğrulama e-postası geliyor → giriş → fotoğraf yükleme çalışıyor.
- `https://photomunity.app/tr/privacy` ve `/tr/terms` açılıyor, üstte kırmızı uyarı **yok**.
- `https://photomunity.app/.well-known/apple-app-site-association` ve `/.well-known/assetlinks.json` JSON döndürüyor.

## 6. Yasal metinler

- [ ] `/privacy` ve `/terms` sayfalarındaki metinler **taslaktır** (`photomunity-web/src/lib/legal.ts`). Yayından önce bir hukukçuya okutun: KVKK aydınlatma metni, yurt dışına aktarım, VERBİS yükümlülüğü, mesafeli satış / abonelik koşulları.
- [ ] Gizlilik politikası adresi mağaza kayıtlarında kullanılacak: `https://photomunity.app/tr/privacy` (İngilizce: `/en/privacy`).

## 7. Sosyal giriş

- [ ] **Google Cloud → OAuth istemcileri:** Web (yetkili köken `https://photomunity.app`), iOS (bundle `app.photomunity.photomunity`), Android (paket `app.photomunity.photomunity` + imza SHA-1). Kimlikleri API'de `GOOGLE_CLIENT_IDS`, web'de `NEXT_PUBLIC_GOOGLE_CLIENT_ID`, mobilde `GOOGLE_SERVER_CLIENT_ID` (web istemcisi) ve `GOOGLE_IOS_CLIENT_ID` olarak verin. iOS istemcisinin ters çevrilmiş kimliğini `ios/Runner/Info.plist` URL şemalarına ekleyin.
- [ ] **Apple:** Services ID (web için, dönüş adresi `https://photomunity.app`), App ID'de "Sign in with Apple" açık.

## 8. Push (Firebase)

- [ ] Firebase projesi; iOS (`app.photomunity.photomunity`) ve Android (`app.photomunity.photomunity`) uygulamalarını ekleyin.
- [ ] `GoogleService-Info.plist` → `photomunity-mobile/ios/Runner/`, `google-services.json` → `photomunity-mobile/android/app/`.
- [ ] Apple Developer'da APNs anahtarı (.p8) oluşturup Firebase → Cloud Messaging'e yükleyin.
- [ ] Servis hesabı JSON'u → API `FCM_SERVICE_ACCOUNT_JSON`.

## 9. Ödemeler

- [ ] **Stripe:** "Photomunity Pro" ürünü, aylık ve yıllık fiyat → `STRIPE_PRICE_*`. Webhook: `https://api.photomunity.app/api/v1/billing/webhooks/stripe` (olaylar: `checkout.session.completed`, `customer.subscription.created/updated/deleted`). Müşteri portalını açın.
- [ ] **App Store Connect / Play Console:** otomatik yenilenen abonelikler `photomunity_pro_monthly` ve `photomunity_pro_yearly`.
- [ ] **RevenueCat:** iki mağazayı bağlayın, `pro` yetkisi ve iki paketli *current offering*. Webhook: `https://api.photomunity.app/api/v1/billing/webhooks/revenuecat`, Authorization = `REVENUECAT_WEBHOOK_AUTH`. Genel SDK anahtarları → mobil `RC_IOS_KEY`, `RC_ANDROID_KEY`.

## 10. Reklamlar (AdMob)

- [ ] AdMob'da iOS ve Android uygulamaları ve birer 300×250 reklam birimi.
- [ ] iOS uygulama kimliği: `photomunity-mobile/ios/Flutter/Secrets.xcconfig.example` → `Secrets.xcconfig`, `ADMOB_APP_ID` doldurun.
- [ ] Android uygulama kimliği: derlemede `ADMOB_APP_ID` ortam değişkeni.
- [ ] `ios/Runner/Info.plist` içine AdMob belgesindeki `SKAdNetworkItems` listesini ekleyin.
- [ ] AdMob → Gizlilik ve mesajlaşma: GDPR ve iOS ATT mesajlarını yayınlayın.

## 11. iOS yayını

- [ ] Apple Developer → Identifiers: `app.photomunity.photomunity`; Associated Domains, Sign in with Apple, Push Notifications açık.
- [ ] App Store Connect'te uygulamayı oluşturun.
- [ ] Derleme:

```bash
cd photomunity-mobile
flutter build ipa --release \
  --dart-define=API_URL=https://api.photomunity.app/api/v1 \
  --dart-define=WEB_URL=https://photomunity.app \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=... --dart-define=GOOGLE_IOS_CLIENT_ID=... \
  --dart-define=RC_IOS_KEY=appl_... \
  --dart-define=ADMOB_BANNER_IOS=ca-app-pub-.../...
```

- [ ] `build/ios/ipa/*.ipa` dosyasını Transporter ya da Xcode Organizer ile yükleyin → TestFlight'ta deneyin → incelemeye gönderin.
- [ ] İnceleme için demo hesap bilgisi, gizlilik politikası adresi, gizlilik "beslenme etiketi" (toplanan veriler), yaş derecelendirmesi.

## 12. Android yayını

- [ ] Yükleme anahtarı:

```bash
keytool -genkey -v -keystore ~/photomunity-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

- [ ] `photomunity-mobile/android/key.properties.example` → `key.properties`, bilgileri doldurun. Anahtarı ve şifreyi güvenli bir yerde yedekleyin; kaybedilirse güncelleme yayınlanamaz.
- [ ] Derleme:

```bash
cd photomunity-mobile
ADMOB_APP_ID=ca-app-pub-...~... flutter build appbundle --release \
  --dart-define=API_URL=https://api.photomunity.app/api/v1 \
  --dart-define=WEB_URL=https://photomunity.app \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=... \
  --dart-define=RC_ANDROID_KEY=goog_... \
  --dart-define=ADMOB_BANNER_ANDROID=ca-app-pub-.../...
```

- [ ] `build/app/outputs/bundle/release/app-release.aab` → Play Console, önce dahili test kanalı.
- [ ] Play Console → Uygulama bütünlüğü → **Uygulama imzalama anahtarı SHA-256** değerini web'de `ANDROID_CERT_SHA256` olarak verin (App Links için), SHA-1'i Google OAuth Android istemcisine ekleyin.
- [ ] Veri güvenliği formu, içerik derecelendirmesi, hedef kitle, gizlilik politikası adresi.

Not: Bu makinede Android SDK kurulu değil; Android derlemesi henüz hiç denenmedi. Android Studio kurup önce `flutter build apk --debug` ile deneyin.

## 13. Son kontrol (üretimde)

- [ ] Web ve iki uygulamada: kayıt, e-posta doğrulama, giriş (e-posta, Apple, Google), şifre sıfırlama.
- [ ] Fotoğraf yükleme → işlenip akışta görünmesi (işçi çalışıyor), EXIF çipleri.
- [ ] Mesajlaşma gerçek zamanlı; push bildirimi telefona geliyor.
- [ ] Yarışma oluşturma → yayınlama → katılım → oylama (takvim işçi tarafından ilerletiliyor).
- [ ] Pro: Stripe test modu, App Store sandbox, Play test kartı; Pro'da reklam yok.
- [ ] `https://photomunity.app/tr/invite/...` gibi bir bağlantı telefonda uygulamayı açıyor (Universal Links / App Links).
- [ ] Hesap silme: Ayarlar → hesabı sil; fotoğraflar depolamadan da siliniyor.
