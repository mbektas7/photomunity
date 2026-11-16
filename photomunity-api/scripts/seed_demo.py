"""Yerel geliştirme için demo verisi (demo_* hesapları). API üzerinden yükler.

YALNIZCA YEREL GELİŞTİRME İÇİN. Hesaplar: demo_ben, demo_elif, demo_kerem, demo_lena, demo_selin,
demo_mert; e-posta <kullanıcı>@example.com, şifre aşağıdaki PW. Giriş için demo_ben kullanılır
(diğerlerini takip eder, iki toplulukta üyedir, yarışmalarda oy vermiştir).

Örnek görseller düşük çözünürlüklü olduğundan API ve worker'ı gevşek kalite eşikleriyle çalıştırın:
  MIN_LONG_EDGE_PX=800 MIN_FILE_BYTES=1000 MIN_SHARPNESS=0 MAX_HIGHLIGHT_CLIP=1 MAX_SHADOW_CLIP=1 \
    .venv/bin/uvicorn app.main:app --port 8000   (worker için aynı değişkenlerle: .venv/bin/arq app.worker.WorkerSettings)
Sonra:
  .venv/bin/python scripts/seed_demo.py ../design/assets
"Yayla Yolları" yarışmasını oylamaya almak için katılım tarihini veritabanında geçmişe çekin.
"""
import io, json, sys, time, uuid, datetime as dt
from pathlib import Path
import httpx
from PIL import Image

API = "http://localhost:8000/api/v1"
ASSETS = Path(sys.argv[1])
PW = "demo-parola-123"

def exif_bytes(path, make, model, lens, f, exp, iso, focal):
    img = Image.open(path).convert("RGB")
    ex = Image.Exif()
    ex[0x010F] = make; ex[0x0110] = model
    ifd = ex.get_ifd(0x8769)
    ifd[0x829A] = exp; ifd[0x829D] = f; ifd[0x8827] = iso; ifd[0x920A] = focal
    ifd[0xA434] = lens; ifd[0x9003] = "2026:08:12 02:40:00"
    buf = io.BytesIO(); img.save(buf, "JPEG", quality=92, exif=ex); return buf.getvalue()

c = httpx.Client(timeout=60)
def auth(tok): return {"Authorization": f"Bearer {tok}"}

def user(username, name):
    email = f"{username}@example.com"
    r = c.post(f"{API}/auth/register", json={"email": email, "password": PW, "username": username, "display_name": name})
    if r.status_code >= 400:
        r = c.post(f"{API}/auth/login", json={"email": email, "password": PW})
    r.raise_for_status(); d = r.json()
    return d.get("access_token") or d["tokens"]["access_token"]

def patch_me(tok, **kw):
    c.patch(f"{API}/me", json=kw, headers=auth(tok)).raise_for_status()

def upload(tok, asset, title, desc, loc, ex):
    data = exif_bytes(ASSETS / asset, *ex)
    r = c.post(f"{API}/photos/upload-url", json={"content_type": "image/jpeg", "size_bytes": len(data)}, headers=auth(tok)); r.raise_for_status()
    u = r.json()
    up = httpx.post(u["upload_url"], data=u["fields"], files={"file": (asset, data, "image/jpeg")}, timeout=60)
    assert up.status_code < 300, up.text
    meta = {"title": title, "description": desc, "tags": []}
    if loc: meta["location"] = {"latitude": loc[0], "longitude": loc[1], "name": loc[2]}
    r = c.post(f"{API}/photos/{u['photo_id']}/complete", json=meta, headers=auth(tok)); r.raise_for_status()
    return u["photo_id"]

T = {}
for un, name in [("demo_ben", "Deniz Demir"), ("demo_elif", "Elif Yılmaz"), ("demo_kerem", "Kerem Aydın"), ("demo_lena", "Lena Berg"), ("demo_selin", "Selin Kaya"), ("demo_mert", "Mert Özkan")]:
    T[un] = user(un, name)
patch_me(T["demo_lena"], bio="Alp ışığı, yavaş sabahlar. Ekim'de Karadeniz yaylalarındayım; rota önerilerine açığım.", city="München", country="DE", specialties=["landscape", "mountain", "wildlife"])
patch_me(T["demo_elif"], bio="Gece gökyüzü ve yaylalar.", city="Trabzon", country="TR", specialties=["astro", "landscape"])
c.put(f"{API}/me/equipment", json=[{"type": "body", "brand": "Sony", "model": "A7 IV"}, {"type": "lens", "brand": "Sony", "model": "FE 24–70mm F2.8 GM II"}, {"type": "lens", "brand": "Sony", "model": "FE 100–400mm GM"}], headers=auth(T["demo_lena"]))

canon = ("Canon", "Canon EOS R6", "RF15-35mm F2.8 L IS USM")
sony = ("Sony", "ILCE-7M4", "FE 24-70mm F2.8 GM II")
P = {}
P["milky"] = upload(T["demo_elif"], "milkyway.jpg", "Samanyolu, Kaçkarlar", "Pokut'tan yeni ay gecesi. Çekirdek güneybatıdan yükselirken yaylanın üstünde hiç ışık yoktu.", (40.94, 40.98, "Pokut Yaylası"), (*canon, 2.8, 15.0, 4000, 15.0))
P["city"] = upload(T["demo_kerem"], "city.jpg", "Galata gecesi", None, (41.0256, 28.9741, "Galata"), (*canon, 8.0, 6.0, 100, 35.0))
P["fog"] = upload(T["demo_lena"], "fog.jpg", "Sisli sırtlar", None, (40.8, 40.6, "Ayder"), (*sony, 8.0, 1/250, 100, 70.0))
P["forest"] = upload(T["demo_lena"], "forest.jpg", "Orman", None, None, (*sony, 4.0, 1/60, 400, 50.0))
P["plateau"] = upload(T["demo_lena"], "plateau.jpg", "Yayla sabahı", None, None, (*sony, 11.0, 1/125, 100, 24.0))
P["sunset"] = upload(T["demo_selin"], "sunset.jpg", "Akşam, Ege", None, (36.2, 29.64, "Kaş"), (*sony, 11.0, 1/250, 100, 24.0))
P["plateau2"] = upload(T["demo_mert"], "plateau.jpg", "Kavrun", None, None, (*canon, 8.0, 1/200, 100, 35.0))
P["fog2"] = upload(T["demo_ben"], "fog.jpg", "Sabah sisi", None, None, (*canon, 5.6, 1/320, 200, 50.0))
time.sleep(8)

for who in ["demo_elif", "demo_kerem", "demo_lena"]:
    c.post(f"{API}/users/{who}/follow", headers=auth(T["demo_ben"]))
c.post(f"{API}/photos/{P['milky']}/like", headers=auth(T["demo_ben"]))
for who in ["demo_kerem", "demo_lena", "demo_selin", "demo_mert"]:
    c.post(f"{API}/photos/{P['milky']}/like", headers=auth(T[who]))

def community(tok, name, slug, city):
    r = c.post(f"{API}/communities", json={"name": name, "slug": slug, "city": city, "country": "TR", "description": f"{name} topluluğu."}, headers=auth(tok))
    if r.status_code >= 400: print("community", r.status_code, r.text[:200])
    return slug
community(T["demo_elif"], "Trabzon Fotoğraf Evi Derneği", "trabzon-fotograf-evi", "Trabzon")
community(T["demo_elif"], "Astro TR", "astro-tr", "Ankara")
community(T["demo_mert"], "Trabzon FE", "trabzon-fe", "Trabzon")
community(T["demo_kerem"], "Sokak İstanbul", "sokak-istanbul", "İstanbul")
for s in ["astro-tr", "trabzon-fe", "sokak-istanbul"]:
    c.post(f"{API}/communities/{s}/join", headers=auth(T["demo_ben"]))

now = dt.datetime.now(dt.timezone.utc)
def contest(tok, slug, title, desc, rules, d1, d2, d3, prizes):
    body = {"title": title, "description": desc, "rules": rules, "submission_deadline": (now + d1).isoformat(), "voting_end": (now + d2).isoformat(),
            "results_at": (now + d3).isoformat(), "judging_mode": "public", "anonymous": True, "min_votes": 0, "prizes": prizes}
    r = c.post(f"{API}/communities/{slug}/contests", json=body, headers=auth(tok)); print("contest", r.status_code, r.text[:200]); r.raise_for_status()
    cid = r.json()["id"]; r = c.post(f"{API}/contests/{cid}/publish", headers=auth(tok)); print("publish", r.status_code, r.text[:200])
    return cid
C1 = contest(T["demo_elif"], "trabzon-fotograf-evi", "Yayla Yolları", "Karadeniz yaylalarına çıkan yollar, köprüler ve patikalar. Halk oylamasıyla değerlendiriliyor; kareler sonuçlar açıklanana kadar anonim.",
             "Kişi başı tek kare. Kompozit ve yapay zekâ üretimi kabul edilmez. Fotoğraf son bir yıl içinde çekilmiş olmalı.",
             dt.timedelta(hours=2), dt.timedelta(days=2, hours=16), dt.timedelta(days=3, hours=16),
             [{"rank": 1, "title": "Fujifilm X-T5 gövde"}, {"rank": 2, "title": "Lowepro sırt çantası"}, {"rank": 3, "title": "Dernek yıllık üyeliği"}])
for who, pk in [("demo_elif", "milky"), ("demo_kerem", "city"), ("demo_lena", "fog"), ("demo_selin", "sunset"), ("demo_mert", "plateau2")]:
    r = c.post(f"{API}/contests/{C1}/entries", json={"photo_id": P[pk]}, headers=auth(T[who])); print("entry", who, r.status_code, r.text[:120])
C2 = contest(T["demo_elif"], "astro-tr", "Gece Gökyüzü 2026", "Samanyolu, yıldız izleri ve gece manzaraları.", "Kişi başı tek kare.",
             dt.timedelta(days=11, hours=3), dt.timedelta(days=18), dt.timedelta(days=19), [{"rank": 1, "title": "Yıldız izleyici"}])
json.dump({"contest_voting": C1, "contest_open": C2, "photos": P}, open(Path(__file__).parent / "seed_out.json", "w"), indent=1)
print("OK", C1, C2)
