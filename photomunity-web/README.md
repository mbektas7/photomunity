# Photomunity Web — Faz 1–4

Next.js 16 (App Router), React 19, next-intl (TR/EN), TanStack Query, Tailwind CSS 4.

## Çalıştırma

```bash
cp .env.example .env.local     # API_URL ve sosyal giriş client id'leri
npm install
npm run dev                    # http://localhost:3000
```

Backend (`photomunity-api`) `http://localhost:8000` üzerinde çalışıyor olmalı.

## Mimari

Tarayıcı backend'e doğrudan gitmez; tüm istekler Next.js üzerinden geçer:

- `/api/auth/[action]` — login, register, google, apple, logout. Token'lar tarayıcıya JSON olarak verilmez, yalnızca `httpOnly` çerezde tutulur.
- `/api/proxy/[...path]` — diğer tüm API çağrıları. Access token çerezden eklenir; süresi dolduysa refresh token ile sessizce yenilenir.
- Aynı anda gelen yenileme istekleri tek bir istekte birleştirilir. Aksi halde backend'in refresh-token yeniden kullanım koruması tüm oturumları kapatır. **Birden fazla Next.js örneği çalıştırılacaksa bu birleştirme Redis'e taşınmalı.**

Fotoğraf dosyası Next.js'ten de geçmez: tarayıcı presigned POST ile doğrudan depolamaya yükler. Bu yüzden depolamada CORS tanımlı olmalı:

```bash
# MinIO örneği
mc admin config set local api cors_allow_origin="http://localhost:3000,https://photomunity.app"
```

## Sayfalar

| Yol | İçerik |
| --- | --- |
| `/` | Tanıtım sayfası (sunucuda oluşturulur; oturum çerezi olan kullanıcı akışa yönlenir) |
| `/feed` | Takip edilenler + kendi paylaşımları, sonsuz kaydırma |
| `/explore` | Herkese açık profillerden en yeni kareler |
| `/p/[id]` | Fotoğraf detayı, vizör şeridi (EXIF), beğeni, düzenle/sil, işleniyor/reddedildi durumları |
| `/u/[username]` | Profil, ekipman ("Çantasında"), takip, kapalı profil görünümü |
| `/upload` | Sürükle-bırak yükleme, tarayıcıda ön kalite kontrolü, ilerleme, konum |
| `/settings` | Profil, uzmanlık alanları, gizlilik, dil, ekipman, şifre, hesap silme |
| `/map` | Fotoğrafçı ve fotoğraf haritası (MapLibre), uzmanlık filtresi, kümeler, profil/mesaj kartı |
| `/messages`, `/messages/[id]`, `/messages/new?to=` | Gelen kutusu ve istekler, sohbet (fotoğraf ve konum paylaşımı, görüldü, engelleme) |
| `/guide`, `/guide/[slug]` | Ayar rehberi: senaryoya göre başlangıç ayarları, ipuçları, sık hatalar, ilgili hesaplayıcı |
| `/tools` | Hesaplayıcılar: yıldız pozlama süresi (NPF ve 500 kuralı), alan derinliği ve hiperfokal mesafe, ND filtre süresi |
| `/planner` | Gökyüzü planlayıcı: Samanyolu çekirdeği, Ay ve Güneş'in gece boyunca yüksekliği, en iyi pencere, pusula |
| `/pro` | Photomunity Pro: aylık/yıllık plan, Stripe Checkout, abonelik durumu ve yönetimi |
| `/notifications` | Bildirimler (okunmamışlar vurgulu; açılınca okundu sayılır) |
| `/communities`, `/communities/new` | Topluluk listesi, arama, oluşturma |
| `/c/[slug]` | Topluluk sayfası: akış (fotoğraf, haber, yarışma duyurusu), yarışmalar, üyeler |
| `/c/[slug]/settings` | Logo/kapak, bilgiler, yöneticiler (kullanıcı adıyla ekleme, e-postayla davet) |
| `/c/[slug]/contests/new` | Yarışma oluşturma formu (taslak olarak kaydedilir) |
| `/contests` | Katılıma açık, oylamada ve sonuçlanan yarışmalar |
| `/contests/[id]` | Paylaşılabilir yarışma sayfası: katılım, misafir için e-posta koduyla oylama, sonuç kürsüsü |
| `/contests/[id]/manage` | Yönetim: yayınlama, jüri ve ağırlıklar, katılımlar ve geçersiz sayma, seçmen özeti, ara sonuç |
| `/contests/[id]/jury` | Jüri ekranı: anonim, tek tek, 1–10 puan, klavye kısayolları |
| `/invite/community`, `/invite/judge` | E-posta davetlerini kabul |
| `/login`, `/register`, `/forgot-password`, `/reset-password`, `/verify-email` | Kimlik doğrulama (`?next=` ile kaldığı yere döner) |

Her yol `/tr/...` ve `/en/...` altında çalışır.

## Tasarım ilkeleri

- Fotoğraf asla kırpılmaz. Keşfet ve profil duvarları her kareyi kendi en-boy oranında dizen "justified" satırlar kullanır (`JustifiedWall`).
- Fotoğraflar köşeli "baskı"dır; yalnızca kontroller yuvarlaktır.
- Açık tema galeri duvarı grisi, koyu tema karanlık oda. Renkler `globals.css` içindeki değişkenlerdedir.
- EXIF, makinenin vizöründeki bilgi şeridi gibi her zaman siyah bir bantta okunur (`Viewfinder`).
- Yazı tipi: Schibsted Grotesk (tek aile). Yazı tipinin "tabular" rakam seti daktilo tarzı olduğu için kullanılmaz; düz rakamlar kullanılır.
- Topluluk logoları yuvarlatılmış kare, kişi avatarları yuvarlak: kurum ile insan ilk bakışta ayrışır.
- Yarışma kareleri oylama ve sonuçlarda da kırpılmaz (sütun düzeni); dikey kareler ekran yüksekliğiyle sınırlanır.

## Tanıtım sayfası ve SEO

Ana sayfa sunucu bileşenidir ve verisini API'den sunucuda çeker (5 dakika önbellekli). Böylece arama motorları içeriği doğrudan görür; oturum çerezi olan kullanıcı sayfa hiç çizilmeden akışa yönlenir.

Bölümler ekran görüntüsü değil, uygulamanın gerçek bileşenleri ve gerçek verisidir:

- **Sayılar şeridi:** fotoğrafçı, yayındaki kare, topluluk, ülke ve açık yarışma sayıları (`GET /stats/public`), vizör şeridi görünümünde. Erken dönemde küçük sayılar gösterilmesin diye `NEXT_PUBLIC_STATS_MIN` (varsayılan 20) kullanıcıdan itibaren görünür.
- **Fotoğraf duvarı:** son paylaşılan kareler, kırpılmadan, en fazla 4 satır.
- **EXIF bölümü:** ayarları dolu, yatay bir gerçek kare ve vizör şeridi.
- **Topluluk bölümü:** şu an açık (yoksa oylamadaki) gerçek bir yarışma.
- **Gökyüzü bölümü:** tarayıcıda hesaplanan bu gecenin planı. Çekirdek bu gece görünmüyorsa (kışın orta enlemlerde) önümüzdeki 150 gün içindeki ilk uygun geceyi gösterir.
- **Rehber bölümü:** API'deki senaryo listesi ve örnek bir NPF sonucu.

Fiyat bölümündeki Pro fiyatı metin dosyasında yazılıdır (`landing.pro_price`); backend'deki `PRO_PRICE_MONTHLY_DISPLAY` değiştirilirse bu metin de güncellenmelidir.

SEO: başlık ve açıklama, canonical, iki dil için `hreflang` (+ `x-default`), Open Graph ve Twitter kartı, uygulamanın yazı tipiyle sunucuda üretilen paylaşım görseli (`/[locale]/opengraph-image`), `WebSite` + `SoftwareApplication` yapılandırılmış verisi, `sitemap.xml` (rehber senaryoları dahil) ve kişisel sayfaları taramaya kapatan `robots.txt`.

## Reklamlar ve Pro

Reklamlar Google AdSense ile `AdSlot` bileşeninden gösterilir: akışta her 8 gönderide bir, Keşfet'in ve Rehber'in altında birer banner. Fotoğraf detayı, mesajlar, yarışma oylaması ve ayarlar bilinçli olarak reklamsızdır. Pro kullanıcılara ve `NEXT_PUBLIC_ADSENSE_CLIENT` boşsa hiç çizilmez. Her reklamın üstünde "Reklam" etiketi ve "Reklamları kaldır" bağlantısı vardır.

**İzin (GDPR/KVKK):** AdSense panelinde *Gizlilik ve mesajlaşma → Avrupa düzenlemeleri* mesajını açın; Google sertifikalı izin penceresi aynı AdSense betiğiyle kendiliğinden gösterilir. Avrupa'daki ziyaretçilere izin penceresi olmadan reklam gösterilmemelidir.

Pro sayfası Stripe Checkout'a yönlendirir; dönüşte (`?status=success`) webhook gelene kadar abonelik durumu kısa süre yoklanır. Mobilde alınmış bir abonelik webde de geçerlidir ve sayfa onu nereden yöneteceğini söyler.

## Gökyüzü hesapları ve hesaplayıcılar

`src/lib/astro.ts` Güneş, Ay (Meeus, bölüm 47 terimleriyle) ve Samanyolu çekirdeğinin konumunu hesaplar. `ephem` kütüphanesine karşı, ufuk üstünde 600 rastgele konum/zamanda en kötü sapma: Güneş 0,22°, Ay 0,57°, çekirdek 0,11°. `src/lib/calculators.ts` NPF kuralını (Michaud'nun tam formülü), alan derinliğini (bulanıklık çemberi = sensör köşegeni / 1442) ve ND sürelerini hesaplar. İki dosya mobildeki Dart karşılıklarıyla ve bir Python başvuru uygulamasıyla 10⁻¹³ hassasiyette aynı sonucu verir.

## Harita

MapLibre GL 6 ile çizilir; işaretçiler HTML öğesidir (avatar, küme rozeti, küçük resim), kümeleme sunucuda yapılır. Altlık varsayılan olarak OpenFreeMap'ten gelir (ücretsiz, anahtarsız); `NEXT_PUBLIC_MAP_STYLE_LIGHT` / `_DARK` ile başka bir MapLibre stili verilebilir. MapLibre'nin web worker'ı Next.js paketlemesinde yolunu kaybettiği için `npm install` sırasında `public/vendor/` altına sürüm numaralı adla kopyalanır ve oradan yüklenir (`scripts/copy-maplibre-worker.mjs`).

## Gerçek zamanlı mesajlar

Oturum açıkken tarayıcı `NEXT_PUBLIC_WS_URL` adresine bağlanır. Erişim token'ı tarayıcıya verilmediği için BFF üzerinden 60 saniyelik bir bilet alınır. Gelen mesajlar sorgu önbelleğine doğrudan yazılır. Bağlantı koparsa artan aralıklarla yeniden denenir; o sırada sayfalar periyodik yenilemeyle çalışmaya devam eder.

## Halk oylaması akışı

Misafir seçmen e-postasını yazar, gelen 6 haneli kodu girer; dönen seçmen token'ı bu tarayıcıda (`localStorage`) oylama bitene kadar saklanır ve BFF üzerinden `X-Voter-Token` başlığıyla backend'e iletilir. Giriş yapmış kullanıcı doğrudan oy verir. Kareler her seçmene farklı sırada, fotoğrafçı adı gizli gelir; kişi kendi karesini "Senin karen" etiketiyle görür ama puanlayamaz.

## Sosyal giriş

`NEXT_PUBLIC_GOOGLE_CLIENT_ID` dolu ise Google Identity Services butonu, `NEXT_PUBLIC_APPLE_CLIENT_ID` dolu ise "Apple ile devam et" butonu görünür. İkisi de `id_token`'ı backend'e iletir; doğrulama sunucuda yapılır. Aynı client id'ler backend'in `GOOGLE_CLIENT_IDS` / `APPLE_CLIENT_IDS` listelerinde olmalı.
