Bu klasörde Fotografya'nın üç projesi var (fotografya-api, fotografya-web, fotografya-mobile) ve yeni onaylanmış tasarımın teslim paketi `design/` klasöründe.

Görevin yeni "Canlı topluluk" tasarımını web ve mobil uygulamalara uygulamak. Bu bir görünüm yenilemesi: API, veri modeli ve iş mantığı değişmeyecek.

Başlamadan önce sırayla oku: `design/README.md` (uygulama rehberi, ekran–dosya eşlemesi), `design/brand.md` (ilkeler), `design/tokens.json`, `design/components/*.md`. Referans ekranlar `design/screens/png/` (görüntü) ve `design/screens/html/` (kesin ölçüler) altında.

Çalışma sırası:

0. Git deposu yoksa `git init` yap ve mevcut durumu "tasarım öncesi" olarak commit et. Sonra `tasarim-canli-topluluk` dalında çalış. Her aşamanın sonunda commit at.
1. Tasarım tokenları — web: `globals.css` + Tailwind teması + Bricolage Grotesque (next/font). Mobil: `theme.dart` Palette + Bricolage Grotesque TTF + lucide_icons_flutter. Açık ve koyu tema.
2. Ortak bileşenler — her iki platformda: Button türleri, PhotoCard, ExifChip, StoryRing, Countdown, alt menü (mobilde yüzen, ortada Yükle; webde giriş yapılmış düzende sol menü).
3. Ekranlar — README'deki eşleme tablosundaki sırayla, önce web (doğrulaması kolay), sonra mobil. Her ekrandan sonra ekran görüntüsü alıp referans PNG ile karşılaştır, farkları düzelt.
4. Çizilmemiş ekranlar — README'deki "Çizilmemiş ekranlar" bölümüne göre aynı sistemi uygula.
5. Son kontrol — `npm run build`, `flutter analyze`, `pytest`; açık ve koyu temada 390 ve 1440 genişlikte ekran görüntüleri.

Kurallar:
- Fotoğraflar asla kırpılmaz (README'deki istisnalar dışında).
- Yeni metinleri TR ve EN çeviri dosyalarına ekle.
- Tasarımda olup API'de karşılığı olmayan bir şey görürsen uydurma; listele ve bana sor.
- Bir değişikliğin kapsamı belirsizse önce sor. Dosya silme.
- Her aşamanın sonunda kısa durum yaz. En sonda: değişen dosyaların özeti, ekran görüntüleri nerede, kalan farklar ve sorular.
