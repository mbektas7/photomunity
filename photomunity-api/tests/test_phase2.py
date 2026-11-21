import re
from datetime import datetime, timedelta, timezone

import pytest

import app.api.v1.communities as communities_api
import app.api.v1.contests as contests_api
import app.services.contests as contest_service
import app.worker as worker
from tests.test_api import register
from tests.test_phase1_complete import notifications, upload_photo

pytestmark = pytest.mark.asyncio

T0 = datetime.now(timezone.utc).replace(microsecond=0)
DEADLINE, VOTING_END, RESULTS = T0 + timedelta(days=7), T0 + timedelta(days=10), T0 + timedelta(days=11)


@pytest.fixture
def clock(monkeypatch):
    """Yarışma saatini ileri sarmak için: clock.set(datetime)."""
    class Clock:
        now = T0

        def set(self, t):
            self.now = t

    c = Clock()
    monkeypatch.setattr(contest_service, "utcnow", lambda: c.now)
    monkeypatch.setattr(worker, "utcnow", lambda: c.now)
    return c


@pytest.fixture
def outbox(monkeypatch):
    sent = []

    async def capture(to, template, locale, link=None, code=None):
        sent.append({"to": to, "template": template, "link": link, "code": code})

    monkeypatch.setattr(contests_api, "send_template", capture)
    monkeypatch.setattr(communities_api, "send_template", capture)
    return sent


def contest_body(mode, **kw):
    return {"title": "Karadeniz'de Sonbahar", "description": "Yaylalarda sonbahar renkleri.", "rules": "Tek kare, kompozit yok.",
            "submission_deadline": DEADLINE.isoformat(), "voting_end": VOTING_END.isoformat(), "results_at": RESULTS.isoformat(),
            "judging_mode": mode, "prizes": [{"rank": 1, "title": "Fujifilm X-T5"}, {"rank": 2, "title": "500 TL"}], **kw}


async def make_community(client, owner):
    r = await client.post("/communities", headers=owner, json={"name": "Trabzon Fotoğraf Evi Derneği", "city": "Trabzon", "country": "tr"})
    assert r.status_code == 201, r.text
    return r.json()["slug"]


async def test_community_membership_admins_invites_posts(client, fake_storage, outbox):
    owner, _ = await register(client, "sahip")
    slug = await make_community(client, owner)
    assert slug == "trabzon-fotograf-evi-dernegi"

    ali, _ = await register(client, "ali")
    await client.post(f"/communities/{slug}/join", headers=ali)
    c = (await client.get(f"/communities/{slug}", headers=ali)).json()
    assert c["member_count"] == 2 and c["my_role"] == "member" and c["owner"]["username"] == "sahip"
    assert (await client.delete(f"/communities/{slug}/join", headers=owner)).json()["error"]["code"] == "owner_cannot_leave"

    # Sistemdeki birini yönetici yap: bildirim gider
    assert (await client.post(f"/communities/{slug}/admins", headers=ali, json={"username": "ali"})).status_code == 403
    assert (await client.post(f"/communities/{slug}/admins", headers=owner, json={"username": "ali"})).status_code == 204
    assert (await client.get(f"/communities/{slug}", headers=ali)).json()["my_role"] == "admin"
    assert (await notifications(client, ali))["items"][0]["text"] == "Sahip seni Trabzon Fotoğraf Evi Derneği topluluğuna yönetici olarak ekledi."

    # Henüz hesabı olmayan birini davet et; kayıt olunca bağlantıyla kabul eder
    r = await client.post(f"/communities/{slug}/invites", headers=owner, json={"email": "ayse.hoca@example.com"})
    assert r.json()["status"] == "invited"
    token = re.search(r"token=([\w-]+)", outbox[-1]["link"]).group(1)
    wrong, _ = await register(client, "baskasi")
    assert (await client.post("/community-invites/accept", headers=wrong, json={"token": token})).status_code == 403
    ayse, _ = await register(client, "ayse", email="ayse.hoca@example.com")
    assert (await client.post("/community-invites/accept", headers=ayse, json={"token": token})).json()["my_role"] == "admin"
    assert (await client.post("/community-invites/accept", headers=ayse, json={"token": token})).status_code == 400  # tek kullanımlık
    assert len((await client.get(f"/communities/{slug}/members?role=admin")).json()["items"]) == 2

    # Akış: üye fotoğraf paylaşır, haberi yalnızca yönetici yazar, üye olmayan paylaşamaz
    stranger, _ = await register(client, "yabanci")
    photo = await upload_photo(client, stranger, fake_storage)
    assert (await client.post(f"/communities/{slug}/posts", headers=stranger, json={"kind": "photo", "photo_id": photo})).status_code == 403
    await client.post(f"/communities/{slug}/join", headers=stranger)
    assert (await client.post(f"/communities/{slug}/posts", headers=stranger, json={"kind": "photo", "photo_id": photo})).status_code == 201
    assert (await client.post(f"/communities/{slug}/posts", headers=stranger, json={"kind": "news", "title": "Duyuru"})).status_code == 403
    assert (await client.post(f"/communities/{slug}/posts", headers=ali, json={"kind": "news", "title": "Cumartesi yürüyüşü", "body": "Uzungöl, 06:00"})).status_code == 201
    posts = (await client.get(f"/communities/{slug}/posts")).json()["items"]
    assert [p["kind"] for p in posts] == ["news", "photo"] and posts[1]["photo"]["images"]["thumb"]

    listed = (await client.get("/communities?q=trabzon")).json()
    assert listed[0]["slug"] == slug and listed[0]["member_count"] == 4


async def test_jury_contest_weighted_scoring_and_tiebreak(client, fake_storage, clock, outbox):
    owner, _ = await register(client, "dernek")
    slug = await make_community(client, owner)
    outsider, _ = await register(client, "disaridan")
    assert (await client.post(f"/communities/{slug}/contests", headers=outsider, json=contest_body("jury"))).status_code == 403

    bad = contest_body("jury", voting_end=(DEADLINE - timedelta(days=1)).isoformat())
    assert (await client.post(f"/communities/{slug}/contests", headers=owner, json=bad)).json()["error"]["code"] == "invalid_dates"

    contest = (await client.post(f"/communities/{slug}/contests", headers=owner, json=contest_body("jury"))).json()
    cid = contest["id"]
    assert contest["status"] == "draft" and [p["title"] for p in contest["prizes"]] == ["Fujifilm X-T5", "500 TL"]
    assert (await client.get(f"/contests/{cid}", headers=outsider)).status_code == 404  # taslak gizli
    assert (await client.post(f"/contests/{cid}/publish", headers=owner)).json()["error"]["code"] == "judges_required"

    chair, _ = await register(client, "baskan")
    member_judge, _ = await register(client, "uye.juri")
    await client.post(f"/contests/{cid}/judges", headers=owner, json={"username": "baskan", "weight": 2})
    await client.post(f"/contests/{cid}/judges", headers=owner, json={"username": "uye.juri", "weight": 1})
    judges = (await client.post(f"/contests/{cid}/judges", headers=owner, json={"email": "davetli.juri@example.com", "weight": 1})).json()
    assert [j["pending"] for j in judges] == [False, False, True]
    assert outbox[-1]["template"] == "judge_invite"
    pending = next(j for j in judges if j["pending"])
    await client.delete(f"/contests/{cid}/judges/{pending['id']}", headers=owner)

    fan, _ = await register(client, "uye")
    await client.post(f"/communities/{slug}/join", headers=fan)
    published = (await client.post(f"/contests/{cid}/publish", headers=owner)).json()
    assert published["status"] == "open"
    assert (await notifications(client, fan))["items"][0]["type"] == "contest_new"
    locked = await client.patch(f"/contests/{cid}", headers=owner, json={"voting_end": (VOTING_END + timedelta(days=1)).isoformat()})
    assert locked.json()["error"]["code"] == "contest_locked"
    assert (await client.patch(f"/contests/{cid}", headers=owner, json={"rules": "Güncel kurallar"})).status_code == 200

    # Katılım: topluluk üyeliği şart değil, kişi başı tek kare, yalnızca kendi fotoğrafı
    entrants = []
    for name in ("katilimci1", "katilimci2", "katilimci3"):
        h, body = await register(client, name)
        photo = await upload_photo(client, h, fake_storage, title=name)
        entrants.append((h, photo))
    h1, p1 = entrants[0]
    assert (await client.post(f"/contests/{cid}/entries", headers=h1, json={"photo_id": entrants[1][1]})).json()["error"]["code"] == "photo_not_eligible"
    ids = []
    for h, photo in entrants:
        r = await client.post(f"/contests/{cid}/entries", headers=h, json={"photo_id": photo})
        assert r.status_code == 201
        ids.append(r.json()["id"])
    assert (await client.post(f"/contests/{cid}/entries", headers=h1, json={"photo_id": p1})).json()["error"]["code"] == "already_entered"
    assert (await client.get(f"/contests/{cid}/entries", headers=fan)).json() == []  # katılım sürerken gizli
    assert (await client.get(f"/contests/{cid}", headers=h1)).json()["my_entry"]["photo_id"] == p1

    # Değerlendirme
    clock.set(DEADLINE + timedelta(hours=1))
    assert (await client.post(f"/contests/{cid}/entries", headers=fan, json={"photo_id": p1})).json()["error"]["code"] == "contest_not_open"
    view = (await client.get(f"/contests/{cid}/entries", headers=chair)).json()
    assert len(view) == 3 and all(e["user"] is None for e in view)  # anonim
    assert (await client.get(f"/contests/{cid}/entries", headers=fan)).json() == []
    assert (await client.put(f"/contests/{cid}/jury/scores/{ids[0]}", headers=fan, json={"score": 10})).status_code == 403
    assert (await client.post(f"/contests/{cid}/votes", headers=fan, json={"entry_id": ids[0], "stars": 5})).json()["error"]["code"] == "voting_not_public"

    # Başkan (ağırlık 2): 9, 6, 7   Üye (ağırlık 1): 3, 9, 7  → hepsi (ağırlıklı) 7.0; eşitlikte başkanın puanı belirler
    for judge, scores in ((chair, (9, 6, 7)), (member_judge, (3, 9, 7))):
        for entry_id, s in zip(ids, scores):
            assert (await client.put(f"/contests/{cid}/jury/scores/{entry_id}", headers=judge, json={"score": s})).status_code == 204
    preview = (await client.get(f"/contests/{cid}/results", headers=owner)).json()
    assert [r["score"] for r in preview] == [7.0, 7.0, 7.0]
    assert (await client.get(f"/contests/{cid}/results", headers=fan)).status_code == 403

    clock.set(RESULTS + timedelta(minutes=1))
    results = (await client.get(f"/contests/{cid}/results")).json()
    assert [r["entry"]["id"] for r in results] == [ids[0], ids[2], ids[1]]
    assert [r["prize"] for r in results] == ["Fujifilm X-T5", "500 TL", None]
    assert results[0]["entry"]["user"]["username"] == "katilimci1" and results[0]["count"] == 2
    won = (await notifications(client, h1))["items"][0]
    assert won["type"] == "contest_won" and "1. oldun" in won["text"]
    finished = (await client.get(f"/contests/{cid}/entries")).json()
    assert finished[0]["rank"] == 1 and finished[0]["user"]["username"] == "katilimci1"

    # Profilde ödüllü kareler: ilk üçe girenler, ödül adıyla
    awards = (await client.get("/users/katilimci1/awards")).json()
    assert [(a["rank"], a["prize"], a["contest_id"], a["photo"]["id"]) for a in awards] == [(1, "Fujifilm X-T5", cid, p1)]
    assert (await client.get("/users/katilimci2/awards")).json()[0]["rank"] == 3
    assert (await client.get("/users/uye/awards")).json() == []


async def test_public_voting_with_email_codes_and_bayesian_ranking(client, fake_storage, clock, outbox):
    owner, _ = await register(client, "yonetim")
    slug = await make_community(client, owner)
    cid = (await client.post(f"/communities/{slug}/contests", headers=owner, json=contest_body("public", min_votes=2))).json()["id"]
    await client.post(f"/contests/{cid}/publish", headers=owner)

    entrants = []
    for name in ("foto1", "foto2", "foto3"):
        h, _ = await register(client, name)
        photo = await upload_photo(client, h, fake_storage)
        entrants.append((h, (await client.post(f"/contests/{cid}/entries", headers=h, json={"photo_id": photo})).json()["id"]))
    (_, e1), (_, e2), (h3, e3) = entrants

    assert (await client.post(f"/contests/{cid}/vote/request-code", json={"email": "a@example.com"})).json()["error"]["code"] == "contest_not_judging"
    clock.set(DEADLINE + timedelta(hours=2))

    async def guest(email):
        assert (await client.post(f"/contests/{cid}/vote/request-code", json={"email": email})).status_code == 202
        code = outbox[-1]["code"]
        assert outbox[-1]["to"] == email
        r = await client.post(f"/contests/{cid}/vote/verify", json={"email": email, "code": code})
        assert r.status_code == 200, r.text
        return {"X-Voter-Token": r.json()["voter_token"]}

    assert (await client.post(f"/contests/{cid}/vote/request-code", json={"email": "x@mailinator.com"})).json()["error"]["code"] == "disposable_email"
    await client.post(f"/contests/{cid}/vote/request-code", json={"email": "deneme@example.com"})
    assert (await client.post(f"/contests/{cid}/vote/verify", json={"email": "deneme@example.com", "code": "000000" if outbox[-1]["code"] != "000000" else "111111"})).json()["error"]["code"] == "invalid_code"
    assert (await client.post(f"/contests/{cid}/votes", json={"entry_id": e1, "stars": 5})).json()["error"]["code"] == "voter_required"

    g1 = await guest("Mehmet.Kaya@gmail.com")
    entries = (await client.get(f"/contests/{cid}/entries", headers=g1)).json()
    assert len(entries) == 3 and all(e["user"] is None and e["my_stars"] is None for e in entries)
    await client.post(f"/contests/{cid}/votes", headers=g1, json={"entry_id": e1, "stars": 5})
    await client.post(f"/contests/{cid}/votes", headers=g1, json={"entry_id": e2, "stars": 3})
    # Aynı Gmail kutusunun varyasyonu aynı seçmendir: oy eklenmez, güncellenir
    g1b = await guest("mehmetkaya+yarisma@googlemail.com")
    await client.post(f"/contests/{cid}/votes", headers=g1b, json={"entry_id": e2, "stars": 3})
    mine = {e["id"]: e["my_stars"] for e in (await client.get(f"/contests/{cid}/entries", headers=g1b)).json()}
    assert mine[e1] == 5 and mine[e2] == 3

    g2 = await guest("zeynep@example.com")
    await client.post(f"/contests/{cid}/votes", headers=g2, json={"entry_id": e1, "stars": 5})

    # Giriş yapmış kullanıcı da oy verir; kendi karesine veremez
    await client.post(f"/contests/{cid}/votes", headers=h3, json={"entry_id": e1, "stars": 4})
    await client.post(f"/contests/{cid}/votes", headers=h3, json={"entry_id": e2, "stars": 2})
    assert (await client.post(f"/contests/{cid}/votes", headers=h3, json={"entry_id": e3, "stars": 5})).json()["error"]["code"] == "cannot_vote_own"

    summary = (await client.get(f"/contests/{cid}/summary", headers=owner)).json()
    assert summary["voters"] == 3 and summary["votes"] == 5

    # e1: [5,5,4] e2: [3,2] e3: oy yok. Genel ortalama 3.8, m=2
    # e1 = 3/5·4.667 + 2/5·3.8 = 4.32   e2 = 2/4·2.5 + 2/4·3.8 = 3.15
    clock.set(RESULTS + timedelta(hours=1))
    results = (await client.get(f"/contests/{cid}/results")).json()
    assert [(r["entry"]["id"], r["rank"], r["score"], r["count"]) for r in results] == [
        (e1, 1, 4.32, 3), (e2, 2, 3.15, 2), (e3, None, None, 0)]
    assert (await client.post(f"/contests/{cid}/votes", headers=g2, json={"entry_id": e2, "stars": 5})).json()["error"]["code"] == "contest_not_judging"


async def test_deadline_reminder_and_cron_finalize(client, fake_storage, clock):
    owner, _ = await register(client, "kurucu")
    slug = await make_community(client, owner)
    lazy, _ = await register(client, "unutkan")
    eager, _ = await register(client, "hevesli")
    for h in (lazy, eager):
        await client.post(f"/communities/{slug}/join", headers=h)
    cid = (await client.post(f"/communities/{slug}/contests", headers=owner, json=contest_body("public"))).json()["id"]
    await client.post(f"/contests/{cid}/publish", headers=owner)
    photo = await upload_photo(client, eager, fake_storage)
    await client.post(f"/contests/{cid}/entries", headers=eager, json={"photo_id": photo})

    clock.set(DEADLINE - timedelta(hours=20))
    await worker.contest_tick({})
    await worker.contest_tick({})  # ikinci çalıştırma tekrar bildirim üretmez
    lazy_types = [n["type"] for n in (await notifications(client, lazy))["items"]]
    eager_types = [n["type"] for n in (await notifications(client, eager))["items"]]
    assert lazy_types.count("contest_deadline") == 1 and "contest_deadline" not in eager_types

    clock.set(RESULTS + timedelta(minutes=5))
    await worker.contest_tick({})
    assert (await notifications(client, eager))["items"][0]["type"] == "contest_results"


async def test_admin_who_is_judge_and_own_entry_flags(client, fake_storage, clock):
    owner, _ = await register(client, "baskan.yonetici")
    slug = await make_community(client, owner)
    cid = (await client.post(f"/communities/{slug}/contests", headers=owner, json=contest_body("jury"))).json()["id"]
    await client.post(f"/contests/{cid}/judges", headers=owner, json={"username": "baskan.yonetici", "weight": 2})
    await client.post(f"/contests/{cid}/publish", headers=owner)
    c = (await client.get(f"/contests/{cid}", headers=owner)).json()
    assert c["my_role"] == "admin" and c["is_judge"] is True

    # Yönetici-jüri aynı zamanda katılımcı: kendi karesini tanır ama puanlayamaz
    mine = await upload_photo(client, owner, fake_storage)
    other, _ = await register(client, "diger")
    theirs = await upload_photo(client, other, fake_storage)
    own_entry = (await client.post(f"/contests/{cid}/entries", headers=owner, json={"photo_id": mine})).json()["id"]
    await client.post(f"/contests/{cid}/entries", headers=other, json={"photo_id": theirs})
    clock.set(DEADLINE + timedelta(hours=1))
    judge_view = (await client.get(f"/contests/{cid}/entries", headers=owner)).json()
    assert all(e["user"] is None for e in judge_view)  # yönetici de olsa jüri görünümü anonim
    assert [e["mine"] for e in judge_view if e["id"] == own_entry] == [True]
    assert (await client.put(f"/contests/{cid}/jury/scores/{own_entry}", headers=owner, json={"score": 10})).json()["error"]["code"] == "cannot_vote_own"
    admin_view = (await client.get(f"/contests/{cid}/entries?view=admin", headers=owner)).json()
    assert all(e["user"] is not None for e in admin_view)
