# Photomunity — Yayına alma rehberi

Sıra önemlidir: önce alan adı ve sunucu, sonra web/API, en son mobil uygulamalar.
Her adımın sonunda **Kontrol** satırındaki denemeyi yapın.

Kurulum tek bir Linux sunucusunda (VPS) Docker ile yapılır. Tüm yapılandırma `deploy/` klasöründe:

| Dosya | Ne |
| --- | --- |
| `deploy/docker-compose.yml` | Caddy (otomatik HTTPS), web, API, işçi, PostgreSQL+PostGIS, Redis, MinIO (fotoğraflar), günlük yedek |
| `deploy/Caddyfile` | Alan adı yönlendirmeleri ve güvenlik başlıkları |
| `deploy/.env.example` | Sunucu ayarları (kopyalanıp doldurulur) |
| `deploy/setup-server.sh` | Temiz Ubuntu sunucusunu hazırlar |
| `.github/workflows/ci.yml` | Her push'ta testler; `main` testleri geçerse sunucuya otomatik yayın |

Adresler:

| Adres | Ne |
| --- | --- |
| `https://photomunity.app` | Web |
| `https://api.photomunity.app` | API (WebSocket dahil) |
| `https://media.photomunity.app` | Fotoğraflar (yalnızca `photos/` herkese açık) ve doğrudan yükleme |

---

## 0. Ön koşullar (hesaplar)

- [ ] Alan adı: `photomunity.app`
- [x] Kod deposu: https://github.com/mbektas7/photomunity
- [ ] Sunucu (VPS): **Ubuntu 24.04, en az 2 vCPU / 4 GB RAM / 80 GB disk**. Örn. Hetzner CX22 ya da DigitalOcean 4 GB. Fotoğraflar sunucu diskinde durur; disk dolmaya yaklaşınca büyütülür.
- [ ] Apple Developer Program (yıllık ücretli), Google Play Console (tek seferlik ücretli)
- [ ] Firebase, Google Cloud (OAuth), Resend, Stripe, RevenueCat, AdMob, AdSense (isteğe bağlı)

## 1. Sunucuyu aç ve DNS'i yönlendir

- [ ] Sunucuyu oluştururken kendi SSH anahtarını ekle (şifreyle giriş yerine).
- [ ] Alan adı panelinde sunucunun IP adresine **A kayıtları** (IPv6 varsa AAAA da):

| Ad | Tür | Değer |
| --- | --- | --- |
| `@` | A | sunucu IP |
| `www` | A | sunucu IP |
| `api` | A | sunucu IP |
| `media` | A | sunucu IP |

**Kontrol:** `ping api.photomunity.app` sunucu IP'sini gösteriyor (DNS yayılması birkaç dakika–birkaç saat sürebilir).

## 2. Sunucuyu hazırla

Kendi bilgisayarından:

```bash
ssh root@SUNUCU_IP
```

Sunucuda:

```bash
curl -fsSL https://raw.githubusercontent.com/mbektas7/photomunity/main/deploy/setup-server.sh -o setup.sh
bash setup.sh
```

Depo özelse bu adres erişilemez; o durumda dosyanın içeriğini kopyalayıp sunucuda `nano setup.sh` ile yapıştır.

Betik şunları yapar: sistem güncellemesi, otomatik güvenlik güncellemeleri, güvenlik duvarı (yalnızca 22/80/443), fail2ban, 2 GB takas, Docker ve `deploy` kullanıcısı.

## 3. Kodu sunucuya al

Depo özel olduğu için sunucuya **salt okunur bir anahtar** (deploy key) verilir. Sunucuda `deploy` kullanıcısıyla:

```bash
su - deploy
ssh-keygen -t ed25519 -f ~/.ssh/github -N ""
cat ~/.ssh/github.pub
```

- [ ] Çıkan satırı GitHub → depo → Settings → Deploy keys → *Add deploy key* (yazma izni **kapalı**).

```bash
printf 'Host github.com\n  IdentityFile ~/.ssh/github\n' >> ~/.ssh/config
git clone git@github.com:mbektas7/photomunity.git /opt/photomunity
```

## 4. Ayarları doldur

```bash
cd /opt/photomunity/deploy
cp .env.example .env
nano .env
```

Zorunlu alanlar: `DOMAIN`, `ACME_EMAIL`, `POSTGRES_PASSWORD`, `MINIO_ROOT_PASSWORD`, `JWT_SECRET`, `RESEND_API_KEY`, `NEXT_PUBLIC_LEGAL_ENTITY`, `NEXT_PUBLIC_CONTACT_EMAIL`. Rastgele değerler için:

```bash
openssl rand -hex 32
```

API, eksik ya da geliştirme değerleriyle **açılmaz** ve neyin eksik olduğunu kayıtlara yazar. Diğer alanlar (sosyal giriş, push, ödeme) boşsa ilgili özellik kapalı kalır; sonradan doldurup 5. adımdaki komutla güncelleyebilirsin.

> `.env` sunucudaki tek gizli dosyadır. Bir kopyasını parola yöneticinde sakla.

## 5. Başlat

```bash
docker compose up -d --build
```

İlk derleme birkaç dakika sürer. Veritabanı şeması API her açıldığında otomatik güncellenir; HTTPS sertifikaları Caddy tarafından otomatik alınır ve yenilenir.

**Kontrol:**

```bash
docker compose ps                          # tüm servisler "Up", api "healthy"
curl https://api.photomunity.app/health    # {"status":"ok"}
docker compose logs -f api worker          # hata var mı
```

- `https://photomunity.app/tr` açılıyor; kayıt → doğrulama e-postası → giriş → fotoğraf yükleme çalışıyor.
- `https://photomunity.app/tr/privacy` açılıyor, üstte kırmızı uyarı **yok**.
- `https://photomunity.app/.well-known/apple-app-site-association` JSON döndürüyor.

Demo verisi (`scripts/seed_demo.py`) üretimde **çalıştırılmaz**.

### Günlük işler

| İş | Komut (`/opt/photomunity/deploy` içinde) |
| --- | --- |
| Elle güncelleme | `git pull && docker compose up -d --build` |
| Kayıtlar | `docker compose logs -f --tail=100 api` |
| Yeniden başlatma | `docker compose restart api worker` |
| Yedekler | `ls backups/` (her gün bir `.dump`, 14 gün tutulur) |
| Yedekten dönme | `docker compose exec -T db pg_restore -U photomunity -d photomunity --clean < backups/DOSYA.dump` |

**Yedekler sunucunun kendisinde durur.** Sunucu kaybına karşı `backups/` klasörünü ve fotoğrafları (`miniodata` birimi) düzenli olarak başka bir yere kopyala; ya da sağlayıcının otomatik sunucu yedeğini (snapshot) aç.

### Otomatik yayın (GitHub Actions)

`main` dalına her push'ta testler çalışır; geçerse sunucu kendini günceller. Bunu açmak için:

1. Kendi bilgisayarında yayına özel bir anahtar üret:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/photomunity_deploy -N ""
```

2. Ortak anahtarı sunucuda `deploy` kullanıcısına ekle (`/home/deploy/.ssh/authorized_keys` dosyasına `~/.ssh/photomunity_deploy.pub` içeriği).
3. Sunucunun parmak izini al:

```bash
ssh-keyscan SUNUCU_IP
```

4. GitHub → depo → Settings:
   - **Secrets and variables → Actions → Secrets:** `DEPLOY_HOST` (sunucu IP), `DEPLOY_SSH_KEY` (`~/.ssh/photomunity_deploy` dosyasının içeriği), `DEPLOY_KNOWN_HOSTS` (3. adımın çıktısı)
   - **Variables:** `DEPLOY_ENABLED` = `true`, `DOMAIN` = `photomunity.app`
   - **Environments:** `production` ortamı oluşur; istersen yayından önce onay isteyecek şekilde ayarlayabilirsin.

**Kontrol:** GitHub → Actions sekmesinde son çalıştırma yeşil ve "deploy" adımı tamamlanmış.

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
