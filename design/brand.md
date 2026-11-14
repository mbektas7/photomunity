# Fotografya

Fotoğrafçıların buluştuğu canlı topluluk. Bu sistem web (Next.js + Tailwind) ve mobil (Flutter) uygulamalarının tek görsel kaynağıdır.

## İlkeler

1. **Fotoğraf kahramandır.** Fotoğraflar asla kırpılmaz; her kare kendi en-boy oranında gösterilir. Yalnızca avatarlar, hikâye halkaları ve yuvarlak küçük resimler kırpılabilir.
2. **Bir mavi, bir turuncu.** `accent` (mavi) tek birincil eylem rengidir: Takip et, Yükle, Oylamaya başla. `live` (turuncu) yalnızca zamanla ilgili canlı durumlar içindir: açık yarışma, oylama, geri sayım. İkisi aynı öğede bir arada kullanılmaz.
3. **Yumuşak ve dokunulabilir.** Kartlar `radius-card`, kart içindeki fotoğraflar `radius-photo`; küçük kontroller hap biçimindedir (`radius-pill`). Her dokunma alanı en az 44 × 44 px.
4. **Çekim bilgisi görünür.** Enstantane, diyafram ve ISO her fotoğrafın altında **ExifChip** olarak durur; bu uygulamanın imzasıdır.
5. **Gölge yok, zemin farkı var.** Kartlar `bg` üzerinde `surface` ile ayrılır. Gölge yalnızca yüzen öğelerde (`shadow-float`) ve ortadaki Yükle düğmesinde (`shadow-accent`).

## Renk

| Token | Ne için |
| --- | --- |
| `bg` / `surface` / `surface-2` | Zemin, kart, kart içi ikincil alan |
| `ink` / `ink-muted` | Ana ve ikincil metin; `ink-subtle` yalnızca etkin olmayan simgeler |
| `accent` + `accent-ink` | Birincil eylem dolgusu ve üzerindeki metin |
| `accent-text` / `accent-tint` | Mavi metin ve seçili durum zemini (beğenilmiş, etkin menü) |
| `live` + `live-ink` | Canlı yarışma rozeti, geri sayım; üzerindeki metin her zaman koyu |
| `danger` | Sil, engelle, hata |

Koyu temada `accent` dolgusu ve `accent-text` ayrı tonlardır: dolgu beyaz yazıyla 4.7:1, metin tonu koyu yüzeyde 7.2:1 verir.

## Tipografi

Tek aile: **Bricolage Grotesque** (Google Fonts, değişken: opsz 12–96, ağırlık 400–700). Başlıklar sıkı harf aralığıyla (`display`, `title`), sayılar `numeral` ile ve tabular rakamla. Tümü büyük harf etiket kullanılmaz.

## Simgeler

Lucide çizgisi: 24 px ızgara, 1.8 çizgi kalınlığı, yuvarlak uçlar; etkin durumda 2.1. Web: `lucide-react`. Flutter: `lucide_icons_flutter`. Beğeni kalbi seçiliyken `accent` dolgulu.

## Metin dili

Sade, eylem odaklı Türkçe. Düğme ne yapacağını söyler: "Fotoğrafınla katıl", "Oylamaya başla", "Takip et". Zaman göreli yazılır ("2 sa önce", "3 gün kaldı"). Hata metinleri ne olduğunu ve nasıl düzeleceğini söyler, özür dilemez.

## Yapılmaması gerekenler

- Fotoğrafı bir kutuya sığdırmak için kırpmak.
- Turuncuyu süs ya da ikinci bir eylem rengi olarak kullanmak.
- Kartlara gölge, gradyan zemin ya da sol kenar çizgisi eklemek.
- `ink-subtle` ile metin yazmak.
