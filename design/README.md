# Photomunity — "Canlı topluluk" tasarımı: uygulama rehberi

Bu klasör, onaylanan yeni tasarımın web (`photomunity-web`) ve mobil (`photomunity-mobile`) uygulamalarına nasıl uygulanacağını anlatır. Tasarım claude.ai'deki bir tasarım tuvalinde ve tasarım sisteminde hazırlandı; buradaki dosyalar onların çevrimdışı kopyasıdır.

## Klasör

| Yol | İçerik |
| --- | --- |
| `brand.md` | Marka kitabı: ilkeler, renk ve tipografi kuralları, metin dili, yapılmaması gerekenler. **Önce bunu oku.** |
| `tokens.json` | Tüm tokenlar: renkler (açık + koyu tema), tipografi, boşluk, köşe, gölge. Tek doğru kaynak. |
| `components/*.md` | Altı bileşenin kuralları: Button, PhotoCard, ExifChip, StoryRing, Countdown, BottomNav. |
| `screens/png/` | 14 ekranın referans görüntüsü (mobil 390×844 @2x, web 1440 genişlik, tam sayfa). |
| `screens/html/` | Aynı ekranların kaynak HTML'i: kesin ölçü, renk, boşluk ve metin için buna bak. Tarayıcıda açılır. |
| `fonts/` | Bricolage Grotesque (değişken, woff2) ve lisansı. Flutter için TTF gerekir, aşağıya bak. |
| `assets/` | Ekranlardaki örnek görseller. Kodla üretilmiş temsili manzaralardır; uygulamaya EKLENMEZ. |

## Değişmeyecekler

- API, veri modeli, iş mantığı, kimlik doğrulama, çeviri anahtarlarının anlamı. Bu bir **görünüm yenilemesidir**.
- Fotoğraf asla kırpılmaz (kendi en-boy oranında gösterilir). Yalnızca avatarlar, hikâye halkaları ve yuvarlak küçük resimler kırpılır.
- Erişilebilirlik: gerçek `button`/`a`/`input`, ikon düğmelerinde `aria-label` / `Semantics`, en az 44 px dokunma alanı, metin kontrastı 4.5:1 (tokenlar buna göre seçildi).
- İki dil (TR/EN). Tasarımda yeni metin varsa her iki dile anahtar ekle.

## Ekran → kod eşlemesi

### Mobil (Flutter, `photomunity-mobile/lib/`)

| Referans | Ekran / dosya |
| --- | --- |
| `mobil-01-akis` | Akış — `screens/feed_screen.dart`, kart: `widgets/photo_widgets.dart` (PhotoPrint → PhotoCard) |
| `mobil-02-yarisma-oylama` | Yarışma detayı (halk oylaması) — `screens/contest_screens.dart` |
| `mobil-03-fotograf-detayi` | Fotoğraf detayı — `screens/photo_screen.dart` |
| `mobil-04-profil` | Profil — `screens/profile_screen.dart` |
| `mobil-05-kesfet` | Keşfet — `screens/explore_screen.dart` |
| `mobil-06-harita` | Harita — `screens/map_screen.dart` |
| `mobil-07-sohbet` | Sohbet — `screens/messages_screens.dart` (ChatScreen) |
| `mobil-08-yukleme` | Yükleme — `screens/upload_screen.dart` |
| `mobil-09-gokyuzu-planlayici` | Gökyüzü planlayıcı — `screens/planner_screen.dart` |

### Web (Next.js, `photomunity-web/src/`)

| Referans | Sayfa |
| --- | --- |
| `web-01-akis` | `/feed` ve giriş yapılmış uygulama düzeni: solda menü, ortada akış, sağda canlı yarışmalar ve öneriler |
| `web-02-tanitim` | `/` tanıtım sayfası (sunucu bileşeni, SEO ve gerçek veri bağlantıları korunur) |
| `web-03-fotograf-detayi` | `/p/[id]` |
| `web-04-profil` | `/u/[username]` |
| `web-05-yarisma` | `/contests/[id]` (halk oylaması aşaması; diğer aşamalar aynı düzenle) |

### Çizilmemiş ekranlar

Ayarlar, bildirimler, mesaj listesi, topluluk listesi ve sayfası, yarışma oluşturma/yönetim/jüri, giriş/kayıt, rehber, hesaplayıcılar, Pro, web haritası ve mobil AR görünümü için ayrı çizim yok. Bunlara **aynı sistemi** uygula: `bg` zemin üzerinde `surface` kartlar (`radius-card`), Button bileşeninin türleri, ExifChip, Countdown ve `live` rozeti. Yeni bir görsel desen icat etme; emin olmadığın yerde en yakın çizilmiş ekranı örnek al. AR görünümünde kamera katmanı koyu kalır; yalnızca kontroller (düğmeler, kaydırıcılar, panel) sisteme uyar.

## Platform notları

### Web

- **Yazı tipi:** `next/font/google` ile `Bricolage_Grotesque` (değişken; `axes: ["opsz"]`), Schibsted Grotesk'in yerine.
- **Renkler:** `globals.css` içindeki eski değişkenleri (`--wall`, `--mat`, `--ink`, `--muted`, `--line`, `--accent`…) `tokens.json` adlarıyla değiştir: `--bg`, `--surface`, `--surface-2`, `--ink`, `--ink-muted`, `--ink-subtle`, `--line`, `--ring-idle`, `--accent`, `--accent-ink`, `--accent-text`, `--accent-tint`, `--live`, `--live-ink`, `--danger`. Koyu tema değerleri `prefers-color-scheme: dark` altında. Tailwind 4 `@theme` ile sınıflara bağla (`bg-surface`, `text-ink-muted`, `rounded-card` vb.).
- **Köşe ve gölge:** `radius-photo` 14, `radius-box` 16, `radius-card` 22, `radius-sheet` 26, `radius-pill` 9999; `shadow-float`, `shadow-accent`.
- **Simgeler:** `lucide-react` zaten kurulu; çizgi kalınlığı 1.8, etkin durumda 2.1.
- **Bileşenler:** `components/` altında Button (mevcut `buttonClass` yeni türlerle), PhotoCard (PhotoPrint'in yerine), ExifChip, StoryRing, Countdown. Vizör şeridi (Viewfinder) kartlardan kalkar; fotoğraf detayında yerini 4 EXIF kutusu alır.
- **Mobil web:** alt sekme çubuğu BottomNav görünümüne geçer (yüzen, ortada Yükle).

### Mobil (Flutter)

- **Yazı tipi:** Bricolage Grotesque değişken TTF'i https://github.com/google/fonts/tree/main/ofl/bricolagegrotesque adresinden indir, `assets/fonts/` altına koy ve `pubspec.yaml`'a ekle (Schibsted'in yerine). Lisans: OFL (`fonts/OFL.txt`).
- **Renkler:** `lib/core/theme.dart` içindeki `Palette` alanlarını tokenlarla değiştir (açık + koyu). Eski alan adları yerine token adları: `bg`, `surface`, `surface2`, `ink`, `inkMuted`, `inkSubtle`, `line`, `ringIdle`, `accent`, `accentInk`, `accentText`, `accentTint`, `live`, `liveInk`, `danger`.
- **Simgeler:** `lucide_icons_flutter` paketi (Material ikonlarının yerine; aynı çizgi dili).
- **Widget'lar:** `PhotoCard`, `ExifChip`, `StoryRing`, `Countdown`, `FloatingBottomNav` (ortada yükseltilmiş Yükle; etiketsiz, `Semantics` etiketli).

## Veri gereksinimleri

Tasarımdaki her öğe mevcut API ile karşılanır, iki istisna dışında:

- **StoryRing'deki "görülmemiş içerik" durumu** (`accent` halka): API'de karşılığı yok. Şimdilik üye olunan topluluklar `accent`, açık yarışmalar `live` halkayla gösterilsin; görülme takibi ayrı bir backend işi olarak not edilsin.
- **Akış kartındaki Takip et düğmesi:** yalnızca takip edilmeyen yazarlarda görünür (akış zaten çoğunlukla takip edilenlerden oluştuğu için çoğu kartta görünmez).

Başka bir veri eksikliği görürsen uydurma; listele ve sor.

## Doğrulama

- **Web:** her eşlenen sayfayı 390 ve 1440 genişlikte, açık ve koyu temada ekran görüntüsüyle referans PNG ile karşılaştır. `npm run build` temiz olmalı.
- **Mobil:** `flutter analyze` temiz, emülatörde her ekranın ekran görüntüsünü referansla karşılaştır.
- **Backend:** `pytest` (değişmemeli, yine de çalıştır).
