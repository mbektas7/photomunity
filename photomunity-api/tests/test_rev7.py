"""Revizyon 7: haftalık tema, eleştiri modu, koleksiyonlar, topluluk etkinlikleri, çekim planları, lisans, ekipman keşfi."""
from datetime import timedelta

import pytest
from PIL import ExifTags, Image

import app.services.contests as contest_service
import app.services.plans as plans_service
import app.services.themes as theme_service
import app.worker as worker
from tests.conftest import make_jpeg
from tests.test_admin import make_admin
from tests.test_api import register
from tests.test_phase1_complete import notifications, upload_photo
from tests.test_phase2 import T0, make_community

pytestmark = pytest.mark.asyncio


@pytest.fixture
def clock(monkeypatch):
    class Clock:
        now = T0

        def set(self, t):
            self.now = t

    c = Clock()
    for mod in (theme_service, worker, contest_service):
        monkeypatch.setattr(mod, "utcnow", lambda: c.now)
    return c


def types(page):
    return [n["type"] for n in page["items"]]


# ---------------------------------------------------------------- haftalık tema
async def test_weekly_theme_entries_ranking_and_finalize(client, fake_storage, clock):
    boss, _ = await register(client, "patron")
    ali, _ = await register(client, "ali")
    ayse, _ = await register(client, "ayse")
    cem, _ = await register(client, "cem")
    body = {"title_tr": "Uzun pozlama", "title_en": "Long exposure", "description_tr": "Zamanın akışı",
            "description_en": "The flow of time", "starts_at": (T0 - timedelta(hours=1)).isoformat(),
            "ends_at": (T0 + timedelta(days=7)).isoformat()}
    assert (await client.post("/admin/themes", headers=ali, json=body)).status_code == 403
    await make_admin("patron")
    r = await client.post("/admin/themes", headers=boss, json=body)
    assert r.status_code == 201, r.text
    theme = r.json()
    assert theme["number"] == 1 and theme["status"] == "active" and theme["title_en"] == "Long exposure"
    overlap = await client.post("/admin/themes", headers=boss, json={**body, "title_tr": "x", "title_en": "x"})
    assert overlap.json()["error"]["code"] == "theme_overlap"
    bad = await client.post("/admin/themes", headers=boss, json={**body, "ends_at": (T0 - timedelta(days=1)).isoformat()})
    assert bad.json()["error"]["code"] == "invalid_theme_dates"

    cur = (await client.get("/themes/current", headers={"Accept-Language": "en"})).json()
    assert cur["title"] == "Long exposure" and cur["description"] == "The flow of time" and cur["entry_count"] == 0
    tid = cur["id"]

    pa = await upload_photo(client, ali, fake_storage, title="Şelale")
    pb = await upload_photo(client, ayse, fake_storage, title="Yıldız izi")
    # Başkasının karesiyle katılınamaz
    assert (await client.post(f"/themes/{tid}/entries", headers=cem, json={"photo_id": pa})).json()["error"]["code"] == "photo_not_eligible"
    r = await client.post(f"/themes/{tid}/entries", headers=ali, json={"photo_id": pa})
    assert r.status_code == 201 and r.json()["photo"]["id"] == pa
    assert (await client.post(f"/themes/{tid}/entries", headers=ali, json={"photo_id": pa})).json()["error"]["code"] == "theme_already_entered"
    await client.post(f"/themes/{tid}/entries", headers=ayse, json={"photo_id": pb})

    # Geri çekip yeniden katılma
    assert (await client.delete(f"/themes/{tid}/entries/me", headers=ayse)).status_code == 204
    await client.post(f"/themes/{tid}/entries", headers=ayse, json={"photo_id": pb})

    await client.post(f"/photos/{pa}/like", headers=cem)
    await client.post(f"/photos/{pa}/like", headers=ayse)
    await client.post(f"/photos/{pb}/like", headers=cem)
    top = (await client.get(f"/themes/{tid}/entries?sort=top")).json()["items"]
    assert [e["photo"]["id"] for e in top] == [pa, pb] and top[0]["rank"] == 1 and top[0]["photo"]["like_count"] == 2
    new = (await client.get(f"/themes/{tid}/entries?sort=new")).json()["items"]
    assert new[0]["photo"]["id"] == pb and new[0]["rank"] is None
    await client.post("/users/ayse/follow", headers=cem)
    following = (await client.get(f"/themes/{tid}/entries?sort=following", headers=cem)).json()["items"]
    assert [e["photo"]["id"] for e in following] == [pb]
    assert (await client.get(f"/themes/{tid}/entries?sort=following")).status_code == 401
    mine = (await client.get("/themes/current", headers=ali)).json()
    assert mine["entry_count"] == 2 and mine["my_entry"]["photo"]["id"] == pa

    # Engel: ayşe ali'yi engellerse ali'nin karesini listede görmez
    await client.post("/users/ali/block", headers=ayse)
    assert [e["photo"]["id"] for e in (await client.get(f"/themes/{tid}/entries", headers=ayse)).json()["items"]] == [pb]

    # Süre bitti: katılım kapalı, worker kazananı belirler
    clock.set(T0 + timedelta(days=7, minutes=1))
    assert (await client.post(f"/themes/{tid}/entries", headers=cem, json={"photo_id": pa})).json()["error"]["code"] == "theme_not_active"
    assert (await client.get("/themes/current")).status_code == 404
    await worker.theme_tick({})
    await worker.theme_tick({})  # ikinci çalıştırma tekrar bildirim üretmez
    assert types(await notifications(client, ali)).count("theme_won") == 1
    assert (await notifications(client, ali))["items"][0]["text"] == "Tebrikler! #1 Uzun pozlama temasını en çok beğenilen karenle kazandın."
    en = (await client.get("/notifications", headers={**ali, "Accept-Language": "en"})).json()
    assert en["items"][0]["text"] == "Congratulations! Your photo won weekly theme #1: Long exposure."

    past = (await client.get("/themes?status=past")).json()["items"]
    assert past[0]["status"] == "finished" and past[0]["winner"]["photo"]["id"] == pa and past[0]["winner"]["rank"] == 1
    wins = (await client.get("/users/ali/theme-wins")).json()
    assert wins[0]["number"] == 1 and wins[0]["like_count"] == 2 and wins[0]["photo"]["id"] == pa
    assert (await client.get("/users/ali")).json()["theme_wins"] == 1

    # Yönetim: başlamış tema silinemez, ileri tarihli silinir; düzenleme
    assert (await client.delete(f"/admin/themes/{tid}", headers=boss)).json()["error"]["code"] == "theme_started"
    nxt = (await client.post("/admin/themes", headers=boss, json={
        **body, "starts_at": (T0 + timedelta(days=8)).isoformat(), "ends_at": (T0 + timedelta(days=15)).isoformat()})).json()
    assert nxt["number"] == 2 and nxt["status"] == "scheduled"
    assert (await client.get(f"/themes/{nxt['id']}")).status_code == 404  # başlamamış tema herkese görünmez
    upd = await client.patch(f"/admin/themes/{nxt['id']}", headers=boss, json={"title_en": "Minimalism"})
    assert upd.json()["title_en"] == "Minimalism"
    assert [t["number"] for t in (await client.get("/admin/themes", headers=boss)).json()] == [2, 1]
    assert (await client.delete(f"/admin/themes/{nxt['id']}", headers=boss)).status_code == 204


async def test_theme_lazy_finalize_without_likes(client, fake_storage, clock):
    boss, _ = await register(client, "patron")
    await make_admin("patron")
    ali, _ = await register(client, "ali")
    t = (await client.post("/admin/themes", headers=boss, json={
        "title_tr": "Gölge", "title_en": "Shadow", "starts_at": (T0 - timedelta(hours=1)).isoformat(),
        "ends_at": (T0 + timedelta(days=1)).isoformat()})).json()
    photo = await upload_photo(client, ali, fake_storage)
    await client.post(f"/themes/{t['id']}/entries", headers=ali, json={"photo_id": photo})
    clock.set(T0 + timedelta(days=2))
    out = (await client.get(f"/themes/{t['id']}")).json()
    assert out["status"] == "finished" and out["winner"] is None  # beğeni yoksa kazanan yok
    assert "theme_won" not in types(await notifications(client, ali))


# ---------------------------------------------------------------- eleştiri
async def test_critique_mode(client, fake_storage):
    owner, _ = await register(client, "murat")
    selin, _ = await register(client, "selin")
    deniz, _ = await register(client, "deniz")
    await client.patch("/me", headers=selin, json={"specialties": ["landscape"]})
    photo = await upload_photo(client, owner, fake_storage, title="Sisli sabah")
    plain = await upload_photo(client, owner, fake_storage, title="Normal")
    crit = {"composition": 3, "light": 4, "focus": 4, "editing": 2, "good": " Katmanlar derinlik veriyor. ", "improve": "Ufku indir."}

    assert (await client.put(f"/photos/{plain}/critiques", headers=selin, json=crit)).json()["error"]["code"] == "critique_not_requested"
    r = await client.patch(f"/photos/{photo}", headers=owner, json={"critique_requested": True,
                                                                      "critique_question": "Ufuk çizgisi fazla mı ortada?"})
    assert r.json()["critique_requested"] is True and r.json()["critique_question"].startswith("Ufuk")
    assert (await client.put(f"/photos/{photo}/critiques", headers=owner, json=crit)).json()["error"]["code"] == "cannot_critique_own"
    assert (await client.put(f"/photos/{photo}/critiques", headers=selin, json={**crit, "light": 6})).status_code == 422

    r = await client.put(f"/photos/{photo}/critiques", headers=selin, json=crit)
    assert r.status_code == 200, r.text
    cid = r.json()["id"]
    assert r.json()["good"] == "Katmanlar derinlik veriyor." and r.json()["average"] == 3.25
    # Güncelleme ikinci bildirim üretmez
    await client.put(f"/photos/{photo}/critiques", headers=selin, json={**crit, "editing": 4})
    await client.put(f"/photos/{photo}/critiques", headers=deniz, json={"composition": 5, "light": 5, "focus": 5, "editing": 5})
    page = await notifications(client, owner)
    assert types(page).count("critique_new") == 2
    assert "Selin fotoğrafını eleştirdi." in [n["text"] for n in page["items"]]

    # Faydalı: sahibi ve başkaları işaretler, kendi eleştirisini işaretleyemez
    assert (await client.post(f"/critiques/{cid}/helpful", headers=selin)).json()["error"]["code"] == "cannot_mark_own"
    assert (await client.post(f"/critiques/{cid}/helpful", headers=owner)).status_code == 204
    assert (await client.post(f"/critiques/{cid}/helpful", headers=deniz)).status_code == 204

    lst = (await client.get(f"/photos/{photo}/critiques", headers=owner)).json()
    assert lst["count"] == 2 and lst["items"][0]["id"] == cid and lst["items"][0]["helpful_count"] == 2
    assert lst["items"][0]["helpful_by_me"] is True and lst["items"][0]["author_specialties"] == ["landscape"]
    assert lst["averages"]["composition"] == 4.0 and lst["averages"]["editing"] == 4.5 and lst["can_critique"] is False
    assert lst["critique_question"] == "Ufuk çizgisi fazla mı ortada?"
    mine = (await client.get(f"/photos/{photo}/critiques", headers=selin)).json()
    assert mine["my_critique"]["id"] == cid and mine["can_critique"] is True

    detail = (await client.get(f"/photos/{photo}")).json()
    assert detail["critique_count"] == 2 and detail["critique_requested"] is True
    feed = (await client.get("/critiques/requests", headers=deniz)).json()["items"]
    assert [p["id"] for p in feed] == [photo] and feed[0]["critique_count"] == 2
    assert (await client.get("/critiques/requests", headers=owner)).json()["items"] == []  # kendi kareleri hariç

    # Engellenen kişi eleştiri yazamaz
    await client.post("/users/deniz/block", headers=owner)
    await client.delete(f"/photos/{photo}/critiques/me", headers=deniz)
    assert (await client.put(f"/photos/{photo}/critiques", headers=deniz, json=crit)).status_code in (403, 404)
    assert (await client.get(f"/photos/{photo}/critiques", headers=owner)).json()["count"] == 1

    # Sahibi eleştiriyi silebilir
    assert (await client.delete(f"/critiques/{cid}", headers=deniz)).status_code == 403
    assert (await client.delete(f"/critiques/{cid}", headers=owner)).status_code == 204
    assert (await client.get(f"/photos/{photo}/critiques")).json()["count"] == 0


# ---------------------------------------------------------------- koleksiyonlar
async def test_collections(client, fake_storage):
    elif_, _ = await register(client, "elif")
    other, _ = await register(client, "other")
    p1 = await upload_photo(client, elif_, fake_storage, title="1")
    p2 = await upload_photo(client, elif_, fake_storage, title="2")
    p3 = await upload_photo(client, elif_, fake_storage, title="3")
    foreign = await upload_photo(client, other, fake_storage, title="x")

    bad = await client.post("/collections", headers=elif_, json={"title": "Karadeniz", "photo_ids": [p1, foreign]})
    assert bad.json()["error"]["code"] == "photo_not_eligible"
    r = await client.post("/collections", headers=elif_, json={"title": " Karadeniz ", "description": "Yaylalar",
                                                               "photo_ids": [p2, p1, p2]})
    assert r.status_code == 201, r.text
    col = r.json()
    assert col["title"] == "Karadeniz" and [p["id"] for p in col["photos"]] == [p2, p1] and col["photo_count"] == 2
    assert col["is_mine"] is True and col["owner"]["username"] == "elif"

    col = (await client.post(f"/collections/{col['id']}/photos", headers=elif_, json={"photo_id": p3})).json()
    col = (await client.post(f"/collections/{col['id']}/photos", headers=elif_, json={"photo_id": p3})).json()  # tekrar eklemez
    assert [p["id"] for p in col["photos"]] == [p2, p1, p3]
    col = (await client.put(f"/collections/{col['id']}/photos", headers=elif_, json={"photo_ids": [p3, p1]})).json()
    assert [p["id"] for p in col["photos"]] == [p3, p1]

    second = (await client.post("/collections", headers=elif_, json={"title": "Sokak"})).json()
    cards = (await client.get("/users/elif/collections", headers=other)).json()
    assert [c["title"] for c in cards] == ["Karadeniz", "Sokak"] and len(cards[0]["covers"]) == 2 and "thumb" in cards[0]["covers"][0]
    order = (await client.put("/me/collections/order", headers=elif_, json={"collection_ids": [second["id"]]})).json()
    assert [c["title"] for c in order] == ["Sokak", "Karadeniz"]
    sheet = (await client.get(f"/me/collections?photo_id={p1}", headers=elif_)).json()
    assert {c["title"]: c["contains_photo"] for c in sheet} == {"Sokak": False, "Karadeniz": True}

    # Sahibi olmayan düzenleyemez; başkası görüntüler
    assert (await client.patch(f"/collections/{col['id']}", headers=other, json={"title": "x"})).status_code == 404
    assert (await client.get(f"/collections/{col['id']}", headers=other)).json()["is_mine"] is False
    assert (await client.patch(f"/collections/{col['id']}", headers=elif_, json={"description": None})).json()["description"] is None

    # Silinen kare koleksiyondan düşer
    await client.delete(f"/photos/{p3}", headers=elif_)
    assert [p["id"] for p in (await client.get(f"/collections/{col['id']}")).json()["photos"]] == [p1]
    assert (await client.delete(f"/collections/{col['id']}/photos/{p1}", headers=elif_)).status_code == 204
    assert (await client.delete(f"/collections/{col['id']}", headers=elif_)).status_code == 204
    assert (await client.get(f"/collections/{col['id']}")).status_code == 404

    # Kapalı profil: takip etmeyen göremez
    await client.patch("/me", headers=elif_, json={"is_public": False})
    assert (await client.get("/users/elif/collections", headers=other)).status_code == 403


# ---------------------------------------------------------------- topluluk etkinlikleri
async def test_community_events(client, fake_storage, clock):
    owner, _ = await register(client, "kurucu")
    slug = await make_community(client, owner)
    m1, _ = await register(client, "uye1")
    m2, _ = await register(client, "uye2")
    outsider, _ = await register(client, "yabanci")
    for h in (m1, m2):
        await client.post(f"/communities/{slug}/join", headers=h)

    starts = T0 + timedelta(days=3)
    body = {"title": "Zigana'da Samanyolu gecesi", "description": "Gece yürüyüşü", "starts_at": starts.isoformat(),
            "ends_at": (starts + timedelta(hours=4)).isoformat(), "location_name": "Zigana Geçidi otoparkı",
            "latitude": 40.63, "longitude": 39.41, "capacity": 1, "bring": "Tripod, kırmızı fener"}
    assert (await client.post(f"/communities/{slug}/events", headers=m1, json=body)).status_code == 403
    past = await client.post(f"/communities/{slug}/events", headers=owner, json={**body, "starts_at": (T0 - timedelta(days=1)).isoformat()})
    assert past.json()["error"]["code"] == "invalid_event_dates"
    r = await client.post(f"/communities/{slug}/events", headers=owner, json=body)
    assert r.status_code == 201, r.text
    ev = r.json()
    assert ev["status"] == "upcoming" and ev["can_manage"] is True and ev["my_role"] == "owner" and ev["conversation_id"] is None
    eid = ev["id"]
    note = (await notifications(client, m1))["items"][0]
    assert note["type"] == "event_new" and note["data"]["event_id"] == eid
    assert note["text"] == "Trabzon Fotoğraf Evi Derneği yeni bir etkinlik düzenliyor: Zigana'da Samanyolu gecesi"

    assert (await client.post(f"/events/{eid}/attend", headers=outsider)).json()["error"]["code"] == "not_member"
    out = (await client.post(f"/events/{eid}/attend", headers=m1)).json()
    assert out["attending"] is True and out["attendee_count"] == 1 and out["attendees_preview"][0]["username"] == "uye1"
    assert (await client.post(f"/events/{eid}/attend", headers=m2)).json()["error"]["code"] == "event_full"
    assert (await client.patch(f"/events/{eid}", headers=owner, json={"capacity": 2})).json()["capacity"] == 2
    await client.post(f"/events/{eid}/attend", headers=m2)
    assert (await client.patch(f"/events/{eid}", headers=owner, json={"capacity": 1})).json()["error"]["code"] == "capacity_too_low"
    await client.delete(f"/events/{eid}/attend", headers=m2)
    assert [u["username"] for u in (await client.get(f"/events/{eid}/attendees")).json()] == ["uye1"]

    lst = (await client.get(f"/communities/{slug}/events", headers=m1)).json()
    assert [e["id"] for e in lst["upcoming"]] == [eid] and lst["past"] == [] and lst["upcoming"][0]["attending"] is True
    assert [e["id"] for e in (await client.get("/me/events", headers=m1)).json()] == [eid]

    # 24 saatten az kala bir kez hatırlatma
    clock.set(starts - timedelta(hours=20))
    await worker.reminder_tick({})
    await worker.reminder_tick({})
    assert types(await notifications(client, m1)).count("event_reminder") == 1
    assert "event_reminder" not in types(await notifications(client, m2))

    cancelled = (await client.post(f"/events/{eid}/cancel", headers=owner)).json()
    assert cancelled["status"] == "cancelled"
    assert (await notifications(client, m1))["items"][0]["type"] == "event_cancelled"
    assert (await client.post(f"/events/{eid}/attend", headers=m2)).json()["error"]["code"] == "event_closed"


# ---------------------------------------------------------------- çekim planları
class FakeResponse:
    def __init__(self, payload):
        self.payload = payload

    def raise_for_status(self):
        pass

    def json(self):
        return self.payload


def fake_http(monkeypatch, payload=None, error=False):
    calls = []

    class Client:
        def __init__(self, *a, **kw):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, *a):
            return False

        async def get(self, url, params=None):
            calls.append(params)
            if error:
                raise plans_service.httpx.ConnectError("down")
            return FakeResponse(payload)

    monkeypatch.setattr(plans_service.httpx, "AsyncClient", Client)
    return calls


async def test_shoot_plans_reminders_and_weather(client, clock, monkeypatch):
    me, _ = await register(client, "gezgin")
    target = T0 + timedelta(hours=30)
    body = {"kind": "milkyway", "latitude": 40.63, "longitude": 39.41, "place_name": "Zigana Geçidi",
            "target_at": target.isoformat(), "remind": True, "weather_alert": True, "notes": "Çekirdek GB"}
    assert (await client.post("/me/plans", headers=me, json={**body, "target_at": (T0 - timedelta(hours=1)).isoformat()})).json()["error"]["code"] == "invalid_plan_date"
    r = await client.post("/me/plans", headers=me, json=body)
    assert r.status_code == 201, r.text
    plan = r.json()
    assert plan["status"] == "upcoming" and plan["reminded_day_at"] is None and plan["title"] is None
    pid = plan["id"]
    other, _ = await register(client, "baska")
    assert (await client.get(f"/me/plans/{pid}", headers=other)).status_code == 404
    assert [p["id"] for p in (await client.get("/me/plans", headers=me)).json()["items"]] == [pid]
    assert (await client.get("/me/plans?scope=past", headers=me)).json()["items"] == []

    # 23 saat kala: günlük hatırlatma bir kez
    clock.set(target - timedelta(hours=23))
    await worker.reminder_tick({})
    await worker.reminder_tick({})
    page = await notifications(client, me)
    assert types(page) == ["plan_reminder"] and page["items"][0]["data"]["hours"] == 24
    assert page["items"][0]["text"] == "Hatırlatma: Samanyolu çekimine 24 saat kaldı."
    en = (await client.get("/notifications", headers={**me, "Accept-Language": "en"})).json()
    assert en["items"][0]["text"] == "Reminder: 24 hours until your Milky Way shoot."
    clock.set(target - timedelta(minutes=90))
    await worker.reminder_tick({})
    page = await notifications(client, me)
    assert types(page).count("plan_reminder") == 2 and page["items"][0]["data"]["hours"] == 2

    # Hava: ağ hatası sessizce geçer; bulut eşiği aşınca bir kez uyarı
    clock.set(target - timedelta(hours=20))
    fake_http(monkeypatch, error=True)
    await worker.plan_weather_tick({})
    assert "plan_weather" not in types(await notifications(client, me))
    hour = target.strftime("%Y-%m-%dT%H:00")
    calls = fake_http(monkeypatch, {"hourly": {"time": ["2000-01-01T00:00", hour], "cloud_cover": [0, 72]}})
    await worker.plan_weather_tick({})
    await worker.plan_weather_tick({})
    assert len(calls) == 1 and calls[0]["hourly"] == "cloud_cover" and calls[0]["timezone"] == "UTC"
    page = await notifications(client, me)
    assert types(page).count("plan_weather") == 1 and page["items"][0]["data"]["cloud"] == 72
    assert page["items"][0]["data"]["plan_id"] == pid
    got = (await client.get(f"/me/plans/{pid}", headers=me)).json()
    assert got["last_cloud_cover"] == 72 and got["weather_alerted_at"] is not None

    # Tarih değişince bayraklar sıfırlanır (yeni hedef 24 saatten uzaksa)
    upd = (await client.patch(f"/me/plans/{pid}", headers=me, json={"target_at": (target + timedelta(days=3)).isoformat(),
                                                                      "title": "Perseid", "kind": "meteor"})).json()
    assert upd["reminded_day_at"] is None and upd["weather_alerted_at"] is None and upd["title"] == "Perseid"
    assert (await client.delete(f"/me/plans/{pid}", headers=me)).status_code == 204
    assert (await client.get(f"/me/plans/{pid}", headers=me)).status_code == 404


# ---------------------------------------------------------------- lisans ve ekipman keşfi
def gear_jpeg(model, lens=None, fnumber=1.8, exposure=15.0, iso=3200, seed=1):
    exif = Image.Exif()
    exif[ExifTags.Base.Make] = "Sony"
    exif[ExifTags.Base.Model] = model
    sub = {ExifTags.Base.FNumber: fnumber, ExifTags.Base.ExposureTime: exposure, ExifTags.Base.ISOSpeedRatings: iso}
    if lens:
        sub[ExifTags.Base.LensModel] = lens
    exif[ExifTags.IFD.Exif] = sub
    return make_jpeg(exif=exif, seed=seed)


async def test_license_defaults_and_location(client, fake_storage):
    elif_, _ = await register(client, "elif")
    me = (await client.patch("/me", headers=elif_, json={"default_license": "cc_by_nc", "default_downloads_disabled": True})).json()
    assert me["default_license"] == "cc_by_nc" and me["default_downloads_disabled"] is True
    p1 = await upload_photo(client, elif_, fake_storage)
    d = (await client.get(f"/photos/{p1}")).json()
    assert d["license"] == "cc_by_nc" and d["downloads_disabled"] is True and "full" in d["images"]

    data = make_jpeg()
    up = (await client.post("/photos/upload-url", headers=elif_, json={"content_type": "image/jpeg", "size_bytes": len(data)})).json()
    fake_storage[up["fields"]["key"]] = data
    done = (await client.post(f"/photos/{up['photo_id']}/complete", headers=elif_, json={
        "title": "Uzungöl", "license": "contact", "downloads_disabled": False, "critique_requested": True,
        "location": {"latitude": 40.62, "longitude": 40.29, "name": "Uzungöl"}})).json()
    assert done["license"] == "contact" and done["downloads_disabled"] is False and done["critique_requested"] is True
    d = (await client.get(f"/photos/{up['photo_id']}")).json()
    assert d["location"]["latitude"] == 40.62 and "taken_at" in d["exif"]
    assert (await client.patch(f"/photos/{p1}", headers=elif_, json={"license": "cc_by"})).json()["license"] == "cc_by"
    assert (await client.patch(f"/photos/{p1}", headers=elif_, json={"license": "public_domain"})).status_code == 422


async def test_gear_explore(client, fake_storage):
    a, _ = await register(client, "astro")
    b, _ = await register(client, "sokak")
    viewer, _ = await register(client, "bakan")
    p1 = await upload_photo(client, a, fake_storage, data=gear_jpeg("ILCE-7M4", "FE 14mm F1.8 GM", exposure=20.0, iso=3200))
    p2 = await upload_photo(client, a, fake_storage, data=gear_jpeg("ILCE-7M4", None, fnumber=8.0, exposure=0.004, iso=100, seed=2))
    p3 = await upload_photo(client, b, fake_storage, data=gear_jpeg("ILCE-7M4", "FE 14mm F1.8 GM", exposure=10.0, iso=1600, seed=3))
    await upload_photo(client, b, fake_storage, data=gear_jpeg("X-T5", None, seed=4))
    await client.post(f"/photos/{p3}/like", headers=viewer)

    assert (await client.get("/gear/photos")).json()["error"]["code"] == "gear_required"
    recent = (await client.get("/gear/photos?camera= ilce-7m4 ")).json()["items"]
    assert [p["id"] for p in recent] == [p3, p2, p1]
    popular = (await client.get("/gear/photos?camera=ILCE-7M4&sort=popular&limit=2")).json()
    assert popular["items"][0]["id"] == p3 and popular["next_cursor"] == "2"
    assert len((await client.get(f"/gear/photos?camera=ILCE-7M4&sort=popular&cursor={popular['next_cursor']}")).json()["items"]) == 1
    lens = (await client.get("/gear/photos", params={"lens": "FE 14mm F1.8 GM"})).json()["items"]
    assert {p["id"] for p in lens} == {p1, p3}

    stats = (await client.get("/gear/stats", params={"lens": "fe 14mm f1.8 gm"})).json()
    assert stats["photo_count"] == 2 and stats["photographer_count"] == 2 and len(stats["top_photographers"]) == 2
    s = stats["common_settings"]
    assert s["median_shutter_seconds"] == 15.0 and s["median_shutter_display"] == '15"' and s["median_iso"] == 2400
    assert s["median_aperture"] == 1.8 and s["sample_size"] == 2

    # Engellenen kişinin kareleri listelenmez
    await client.post("/users/sokak/block", headers=viewer)
    assert [p["id"] for p in (await client.get("/gear/photos?camera=ILCE-7M4", headers=viewer)).json()["items"]] == [p2, p1]

    found = (await client.get("/gear/search?q=14mm")).json()
    assert found == [{"kind": "lens", "name": "FE 14mm F1.8 GM", "photo_count": 2}]
    cams = (await client.get("/gear/search?q=i&kind=camera")).json()
    assert cams[0] == {"kind": "camera", "name": "ILCE-7M4", "photo_count": 3}
