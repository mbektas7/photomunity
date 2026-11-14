# PhotoCard

Akıştaki tek fotoğraf: yazar, kırpılmamış kare, beğeni ve çekim bilgisi.

Yapı: üst satırda avatar (38 px), ad (`body-strong`), yer ve zaman (`caption`, `ink-muted`), sağda Takip et (yalnızca takip edilmiyorsa). Ortada fotoğraf kendi oranında, `radius-photo`. Altta beğeni hapı (beğenilmişse `accent-tint` zemin, `accent` dolgulu kalp), Paylaş ve en fazla üç **ExifChip**. Kart `surface`, `radius-card`, iç boşluk `space-3`; gölge yok. Kartlar arası `space-3`.