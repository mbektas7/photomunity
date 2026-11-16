# Photomunity API — Faz 1–4

FastAPI backend. Faz 1: kimlik doğrulama, profil ve ekipman, takip, kalite kontrollü fotoğraf yükleme, EXIF, beğeni, akışlar, bildirimler (uygulama içi + FCM push), avatar/kapak, istek sınırlama, şikayet ve moderasyon. Faz 2: topluluklar, yöneticiler ve davetler, topluluk akışı, fotoğraf yarışmaları (ağırlıklı jüri veya e-posta doğrulamalı halk oylaması).

## Hızlı başlangıç

```bash
cp .env.example .env
docker compose up -d db redis minio minio-init
python -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt
alembic revision --autogenerate -m "initial" && alembic upgrade head
uvicorn app.main:app --reload          # API: http://localhost:8000/docs
arq app.worker.WorkerSettings          # ayrı terminalde: fotoğraf işleme + 5 dakikada bir yarışma görevleri
pytest                                 # 31 test
```

Hepsini konteynerde çalıştırmak için: `docker compose up --build`.

## Fotoğraf yükleme akışı

1. `POST /api/v1/photos/upload-url` `{content_type, size_bytes}` → `photo_id`, `upload_url`, `fields`. Boyut ve format burada ön kontrolden geçer.
2. İstemci dosyayı `upload_url`'e multipart POST ile doğrudan depolamaya yükler (`fields` + `file`). API sunucusu dosya trafiği taşımaz.
3. `POST /api/v1/photos/{id}/complete` `{title, description, tags, location?}` → durum `processing`, iş kuyruğa alınır.
4. Worker: kalite analizi → EXIF → `thumb` / `feed` / `full` WebP türevleri (EXIF ve GPS'siz) → `published`. Reddedilirse orijinal silinir, sebepler `GET /photos/{id}` içinde sahibine TR/EN mesajla döner.

İstemci `GET /photos/{id}` ile durumu yoklar (Faz 1 sonunda push bildirimiyle değişecek).

## Kalite kontrolü

`app/services/quality.py` — eşikler `.env` üzerinden ayarlanır:

| Kontrol | Varsayılan |
| --- | --- |
| Dosya boyutu | 1 MB – 40 MB |
| Uzun kenar | ≥ 2000 px |
| Netlik | Görüntü 8×8 karoya bölünür; Laplacian varyansının 90. yüzdeliği ≥ 60 |
| Patlamış beyaz | Piksellerin ≤ %20'si |
| Tam siyah | Piksellerin ≤ %50'si (astro kareler için cömert) |

Karo bazlı netlik, arka planı bilinçli bulanık portreleri ve büyük kısmı karanlık gökyüzü olan astro kareleri haksız yere reddetmemek için seçildi. Eşikler gerçek fotoğraflarla kalibre edilmeli: ilk haftalarda red kayıtlarındaki `quality` alanı (sharpness, clip oranları) izlenip ayarlanmalı.

## Alınan varsayılan kararlar

- Kimlik: kendi JWT altyapısı (15 dk access, 30 gün refresh, rotasyon ve yeniden kullanım tespiti). Google ve Apple `id_token`'ları JWKS ile sunucuda doğrulanır.
- Kapalı profil: herkes onaysız takip edebilir; fotoğrafları yalnızca sahibi ve takipçileri görür, keşfette çıkmaz.
- Profil konumu ~5 km ızgaraya yuvarlanarak saklanır. Fotoğraftaki EXIF GPS kamuya açılmaz, yalnızca sahibine konum önerisi olarak gösterilir.
- Doğrulanmamış e-postalı bir sosyal hesap, aynı e-postalı mevcut hesaba otomatik bağlanmaz (hesap ele geçirme koruması).
- Hesap silme uygulama içinden kalıcıdır (App Store ve KVKK gereği).

## Bildirimler ve push

Her olay `notifications` tablosuna yazılır; `GET /notifications` metni isteğin diline göre (TR/EN) üretir. Push, kullanıcının tercihine göre (`/me/notification-settings`) Firebase Cloud Messaging HTTP v1 ile gönderilir. Geçersiz cihaz token'ları otomatik silinir. Firebase servis hesabı JSON'unu `FCM_SERVICE_ACCOUNT_FILE` ile verin; verilmezse push'lar log'a yazılır.

## Kötüye kullanım koruması

- **İstek sınırları:** Redis'te sabit pencere (Redis yoksa süreç belleği). Giriş 20/15 dk, kayıt 10/saat (IP başına), yükleme 60/saat ve takip 120/saat (kullanıcı başına), oy kodu 10/saat (IP başına). Ters vekil arkasında `TRUST_PROXY_HEADERS=true`.
- **Şikayet:** `REPORT_AUTO_HIDE_THRESHOLD` (varsayılan 5) farklı kişi aynı fotoğrafı şikayet ederse fotoğraf yönetici kararına kadar gizlenir. Yönetici uçları `/admin/reports`; yönetici yetkisi `users.is_admin`.
- **Otomatik moderasyon:** `MODERATION_PROVIDER=rekognition` ile her yeni fotoğraf ve profil görseli AWS Rekognition'dan geçer. Servis geçici olarak yanıt vermezse yayın engellenmez; şikayet akışı devrede kalır.

## Faz 2: Topluluklar ve yarışmalar

**Roller.** Topluluğu açan kişi *sahip*tir. Sahip, sistemdeki birini kullanıcı adıyla yönetici yapar ya da e-postayla davet eder: e-posta kayıtlıysa kişi hemen yönetici olur, değilse aynı adresle kayıt olunca kabul edeceği bir bağlantı gider. Yöneticiler haber paylaşır ve yarışma düzenler; üyeler kendi fotoğraflarını topluluk akışında paylaşır.

**Yarışma yaşam döngüsü.** Durum tarihlerden hesaplanır, ayrı bir durum alanı tutulmaz:

| Durum | Ne zaman | Kim ne yapabilir |
| --- | --- | --- |
| draft | Yayınlanmadan önce | Yalnızca yöneticiler görür, her alan düzenlenebilir |
| open | Yayın → son gönderim | Giriş yapmış herkes tek kareyle katılır (topluluk üyeliği şart değil); kareler yalnızca yöneticilere görünür |
| judging | Son gönderim → oylama bitişi | Jüri 1–10 puan verir ya da halk 1–5 yıldız verir; fotoğrafçılar varsayılan olarak gizli, sıra her seçmen için farklı karıştırılır |
| closed | Oylama bitişi → sonuç ilanı | Yöneticiler ara sonucu görür |
| finished | Sonuç ilanından sonra | Sonuçlar dondurulur, katılımcılara ve kazananlara bildirim gider |

Yayından sonra tarihler ve değerlendirme yöntemi değiştirilemez; açıklama, kurallar ve ödüller güncellenebilir. Kural dışı kare yönetici tarafından gerekçeyle geçersiz sayılabilir.

**Roller birlikte olabilir.** Bir topluluk yöneticisi aynı yarışmada jüri ve hatta katılımcı olabilir. `ContestOut.is_judge` rolden bağımsız döner. Yönetim listesi yalnızca `GET /contests/{id}/entries?view=admin` ile istenir; yönetici oylama sayfasında herkes gibi anonim seçmen görünümünü alır. Her kare `mine` bilgisi taşır ve kimse kendi karesine oy ya da puan veremez.

**Jüri puanı** = Σ(ağırlık × puan) / Σ(puan veren üyelerin ağırlığı). Eşitlikte en yüksek ağırlıklı üyenin (başkan) puanı belirler.

**Halk puanı** Bayes ortalamasıdır: v oy, R ortalama, C tüm oyların ortalaması ve m = `min_votes` iken `v/(v+m)·R + m/(v+m)·C`. Birkaç 5 yıldızla zirveye oturmayı engeller; eşitlikte çok oy alan öne geçer.

**Tek kişi, tek oy.** Giriş yapmış kullanıcı e-postasıyla, misafir ise e-postasına gelen 6 haneli kodla (10 dk, 5 deneme) tanınır; ikisi de normalleştirilmiş e-postaya bağlanır (büyük/küçük harf, `+etiket` ve Gmail noktaları tek anahtara iner). Geçici e-posta servisleri reddedilir. Kendi karesine oy verilemez. İsteğe bağlı Cloudflare Turnstile (`TURNSTILE_SECRET`). Seçmen IP'leri tuzlanmış hash olarak saklanır; yönetici özeti aynı IP'den çok sayıda seçmen gelen durumları işaretler.

**Zamanlanmış görev** (`contest_tick`, 5 dakikada bir): son gönderimden 24 saat önce henüz katılmamış üyelere bir kez hatırlatma gönderir, sonuç tarihi gelen yarışmaları sonuçlandırır. Sonuçlar ayrıca ilk istekte de tembel olarak dondurulur; worker gecikse bile kullanıcı doğru sonucu görür.

## Faz 3: Harita ve mesajlaşma

**Harita.** `GET /map/photographers?bbox=minLng,minLat,maxLng,maxLat&zoom=&specialty=` ve `GET /map/photos?bbox=&zoom=`. Yalnızca herkese açık ve konumunu paylaşmış profiller (profil konumu ~5 km'ye yuvarlanmış) ve sahibinin bilinçli olarak konum eklediği fotoğraflar döner; EXIF GPS kendiliğinden haritaya düşmez. Kümeleme sunucuda, yakınlaştırmaya göre değişen yarıçaplı mesafe tabanlı açgözlü algoritmayla yapılır (5.000 noktada ~15 ms). Basit ızgara kümelemenin aksine ızgara çizgisi yan yana iki noktayı ayırmaz. 180. meridyeni geçen görünümler desteklenir. Konumlar float kolonlarda `(latitude, longitude)` indeksiyle tutulur; ölçek büyüdüğünde aynı uçlar PostGIS ile değiştirilebilir, istemci sözleşmesi değişmez.

**Mesajlaşma.** İki kişi arasında tek sohbet vardır. Yeni sohbet yalnızca herkese açık profillere başlatılabilir; ilk mesaj alıcının *İstekler* kutusuna düşer. Gönderen kabul edilene kadar en fazla 3 mesaj atabilir. Alıcı kabul eder, yanıt verir (bu da kabul sayılır) ya da reddeder. Reddedilen istek alıcıdan kaybolur, gönderen bilgilendirilmez. Engelleme mesajlaşmayı her iki yönde keser, sohbeti gizler ve karşılıklı takibi kaldırır. Mesajlar metin, fotoğraf ve konum taşıyabilir; okundu bilgisi ("görüldü") tutulur.

**Gerçek zamanlı.** `WS /api/v1/ws?ticket=` (web: `POST /realtime/ticket` ile 60 sn'lik bilet; erişim token'ı tarayıcıya verilmez) ya da `?token=` (mobil). Yeni mesaj ve okundu olayları anında iletilir. Redis varsa olaylar pub/sub ile tüm API süreçlerine dağıtılır; yoksa yalnızca aynı süreçteki bağlantılara gider. Çevrimdışı alıcıya push gönderilir (tercihe bağlı; mesajlar bildirim listesini doldurmaz).

**Sınırlar.** Yeni sohbet 20/gün, mesaj 60/dakika (kullanıcı başına).

## Kamera ayar rehberi

`GET /guides` ve `GET /guides/{slug}` dokuz senaryoyu (Samanyolu, yıldız izi, spor, portre, manzara, uzun pozlama, gece şehir, havai fişek, yaban hayatı) isteğin diline göre döndürür. İçerik `app/content/guides.py` dosyasındadır; web ve mobil aynı kaynaktan okur. Her senaryo ilgili hesaplayıcıyı (`npf`, `dof`, `nd`) ve gerekiyorsa gökyüzü planlayıcısını işaret eder. Test, iki dilde de tüm alanların eksiksiz olduğunu doğrular.

## Faz 4: Pro abonelik

**Tek yetki kaynağı.** `users.is_pro`, kullanıcının tüm abonelik kayıtlarından (`subscriptions`) türetilir: herhangi biri geçerliyse Pro'dur. iOS'ta alınan Pro webde, webde alınan mobilde de geçerlidir. Geçerli durumlar: `active`, `grace` (mağaza ödemeyi yeniden denerken) ve `cancelled` (yenilenmeyecek ama dönem sonuna kadar Pro).

**Mobil (App Store / Google Play) — RevenueCat.** Uygulama RevenueCat'e backend kullanıcı kimliğiyle (`appUserID`) bağlanır. RevenueCat panelinde webhook adresi `POST /api/v1/billing/webhooks/revenuecat`, Authorization başlığı `REVENUECAT_WEBHOOK_AUTH` ile aynı olmalı. RevenueCat kullanıcının mağaza durumunu zaten birleştirdiği için her kullanıcıya tek kayıt tutulur. Satın alma sonrası uygulama `POST /billing/sync` çağırır; `REVENUECAT_SECRET_KEY` verilmişse backend webhook'u beklemeden RevenueCat REST API'den güncel durumu çeker.

**Web — Stripe.** `POST /billing/checkout {plan}` Stripe Checkout oturumu açar (kullanıcı kimliği `client_reference_id` ve abonelik metadata'sına yazılır); `POST /billing/portal` iptal ve kart güncelleme için Stripe müşteri portalını açar. Stripe webhook'u `POST /api/v1/billing/webhooks/stripe`: `checkout.session.completed`, `customer.subscription.created`, `.updated`, `.deleted` olaylarını gönderin. İmza (`STRIPE_WEBHOOK_SECRET`) HMAC-SHA256 ile ve 5 dakikalık zaman toleransıyla doğrulanır.

**Sağlamlık.** Webhook olay kimlikleri saklanır, aynı olay iki kez işlenmez. Saatlik `subscription_tick`, dönemi bitip webhook'u gelmemiş abonelikleri kapatır. Pro kullanıcıların yükleme sınırı saatte 200'dür (normal 60).

| Ayar | Açıklama |
| --- | --- |
| `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET` | Stripe API ve webhook sırları |
| `STRIPE_PRICE_MONTHLY`, `STRIPE_PRICE_YEARLY` | Stripe fiyat kimlikleri (`price_...`) |
| `PRO_PRICE_MONTHLY_DISPLAY`, `PRO_PRICE_YEARLY_DISPLAY` | Web vitrininde gösterilen fiyatlar (varsayılan $1.99 / $17.99) |
| `REVENUECAT_WEBHOOK_AUTH`, `REVENUECAT_SECRET_KEY`, `REVENUECAT_ENTITLEMENT` | RevenueCat webhook başlığı, REST anahtarı, yetki adı (varsayılan `pro`) |

## Sonraki adımlar

- Haftalık e-posta özeti, web push.
- Ücretsiz deneme süresi ve promosyon kodları (Stripe ve mağazalar destekliyor; yalnızca ürün ayarı).
- PostgreSQL üretim geçişi: `alembic revision --autogenerate` ile ilk migration ve PostGIS'e geçiş değerlendirmesi.
