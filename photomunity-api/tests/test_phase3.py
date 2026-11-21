import uuid

import pytest
from starlette.testclient import TestClient

from app.core.database import SessionLocal
from app.main import app
from app.models import User
from tests.test_api import register
from tests.test_phase1_complete import upload_photo

pytestmark = pytest.mark.asyncio


async def test_message_request_flow_limits_and_accept(client, fake_storage):
    a, _ = await register(client, "gezgin")
    b, _ = await register(client, "yerel")

    r = await client.post("/conversations", headers=a, json={"username": "yerel", "body": "Merhaba! Kaçkarlar'da Samanyolu için hangi yaylayı önerirsin?"})
    assert r.status_code == 201, r.text
    cid = r.json()["id"]
    assert r.json()["status"] == "request" and r.json()["is_request_to_me"] is False

    assert [c["id"] for c in (await client.get("/conversations", headers=a)).json()] == [cid]
    assert (await client.get("/conversations", headers=b)).json() == []  # istek gelen kutusunda değil
    req = (await client.get("/conversations?folder=requests", headers=b)).json()
    assert req[0]["is_request_to_me"] and req[0]["unread"] == 1 and req[0]["last_message"]["body"].startswith("Merhaba")
    assert (await client.get("/messages/unread-count", headers=b)).json() == {"inbox": 0, "requests": 1}

    # Kabul edilene kadar en fazla 3 mesaj
    for text in ("Bir de", "Teşekkürler"):
        assert (await client.post(f"/conversations/{cid}/messages", headers=a, json={"body": text})).status_code == 201
    over = await client.post(f"/conversations/{cid}/messages", headers=a, json={"body": "dördüncü"})
    assert over.status_code == 429 and over.json()["error"]["code"] == "request_pending"
    assert (await client.post(f"/conversations/{cid}/messages", headers=a, json={"body": "   "})).json()["error"]["code"] == "empty_message"

    # Alıcının yanıtı isteği kabul eder; fotoğraf ve konum paylaşılabilir
    photo = await upload_photo(client, b, fake_storage)
    reply = await client.post(f"/conversations/{cid}/messages", headers=b, json={
        "body": "Demirkapı yaylasına bak", "photo_id": photo, "location": {"latitude": 40.85, "longitude": 41.1, "name": "Demirkapı"}})
    assert reply.status_code == 201 and reply.json()["photo"]["images"]["thumb"] and reply.json()["location"]["name"] == "Demirkapı"
    conv = (await client.get(f"/conversations/{cid}", headers=b)).json()
    assert conv["status"] == "accepted"
    assert [c["id"] for c in (await client.get("/conversations", headers=b)).json()] == [cid]

    msgs = (await client.get(f"/conversations/{cid}/messages", headers=a)).json()["items"]
    assert [m["body"] for m in msgs] == ["Merhaba! Kaçkarlar'da Samanyolu için hangi yaylayı önerirsin?", "Bir de", "Teşekkürler", "Demirkapı yaylasına bak"]
    assert (await client.get("/messages/unread-count", headers=a)).json()["inbox"] == 1
    await client.post(f"/conversations/{cid}/read", headers=a)
    assert (await client.get("/messages/unread-count", headers=a)).json()["inbox"] == 0
    assert (await client.get(f"/conversations/{cid}", headers=b)).json()["other_last_read_at"] is not None  # "görüldü"

    # Aynı kişiye tekrar "başlat" demek mevcut sohbete yazar
    again = await client.post("/conversations", headers=a, json={"username": "yerel", "body": "Tekrar ben"})
    assert again.json()["id"] == cid
    assert (await client.get("/conversations/with/yerel", headers=a)).json()["id"] == cid


async def test_private_profile_decline_and_block(client):
    a, _ = await register(client, "merakli")
    p, pbody = await register(client, "gizli")
    await client.patch("/me", headers=p, json={"is_public": False})
    r = await client.post("/conversations", headers=a, json={"username": "gizli", "body": "selam"})
    assert r.status_code == 403 and r.json()["error"]["code"] == "cannot_message"

    b, _ = await register(client, "acik")
    cid = (await client.post("/conversations", headers=a, json={"username": "acik", "body": "selam"})).json()["id"]
    assert (await client.post(f"/conversations/{cid}/decline", headers=b)).status_code == 204
    assert (await client.get("/conversations?folder=requests", headers=b)).json() == []
    assert (await client.get(f"/conversations/{cid}", headers=b)).status_code == 404
    # Gönderen fark etmez; yazmaya devam edebilir ama alıcıya ulaşmaz ve sınır geçerlidir
    assert (await client.post(f"/conversations/{cid}/messages", headers=a, json={"body": "orada mısın"})).status_code == 201
    assert (await client.get("/messages/unread-count", headers=b)).json() == {"inbox": 0, "requests": 0}
    await client.post(f"/conversations/{cid}/messages", headers=a, json={"body": "3"})
    assert (await client.post(f"/conversations/{cid}/messages", headers=a, json={"body": "4"})).status_code == 429

    c, _ = await register(client, "rahatsiz")
    cid2 = (await client.post("/conversations", headers=c, json={"username": "acik", "body": "selam"})).json()["id"]
    await client.post("/users/rahatsiz/block", headers=b)
    assert (await client.post(f"/conversations/{cid2}/messages", headers=c, json={"body": "neden?"})).json()["error"]["code"] == "cannot_message"
    assert (await client.get("/conversations?folder=requests", headers=b)).json() == []
    assert (await client.get("/conversations", headers=c)).json() == []
    assert [u["username"] for u in (await client.get("/me/blocks", headers=b)).json()] == ["rahatsiz"]
    await client.delete("/users/rahatsiz/block", headers=b)
    assert len((await client.get("/conversations?folder=requests", headers=b)).json()) == 1


async def test_websocket_delivers_new_messages(client):
    a, abody = await register(client, "yazan")
    b, bbody = await register(client, "okuyan")
    b_token = b["Authorization"].split()[1]
    cid = (await client.post("/conversations", headers=a, json={"username": "okuyan", "body": "ilk"})).json()["id"]

    with TestClient(app) as tc:
        bad = tc.websocket_connect("/api/v1/ws?token=gecersiz")
        with pytest.raises(Exception):
            with bad as ws:
                ws.receive_text()
        with tc.websocket_connect(f"/api/v1/ws?token={b_token}") as ws:
            ws.send_text("ping")
            assert ws.receive_json() == {"type": "pong"}
            r = tc.post(f"/api/v1/conversations/{cid}/messages", headers=a, json={"body": "canlı mesaj"})
            assert r.status_code == 201
            event = ws.receive_json()
            assert event["type"] == "message" and event["conversation_id"] == cid and event["message"]["body"] == "canlı mesaj"

        ticket = tc.post("/api/v1/realtime/ticket", headers=a).json()["ticket"]
        with tc.websocket_connect(f"/api/v1/ws?ticket={ticket}") as ws:
            tc.post(f"/api/v1/conversations/{cid}/read", headers=b)
            assert ws.receive_json()["type"] == "read"


async def _place(username: str, lat: float, lng: float, public: bool = True, specialties=None):
    from sqlalchemy import select

    async with SessionLocal() as db:
        u = await db.scalar(select(User).where(User.username == username))
        u.latitude, u.longitude, u.is_public, u.specialties = lat, lng, public, specialties or []
        await db.commit()


async def test_map_photographers_clustering_filters_and_photos(client, fake_storage):
    for name, lat, lng, spec in [("trabzon1", 41.0, 39.7, ["astro"]), ("trabzon2", 41.0, 39.75, ["landscape"]),
                                 ("rize", 41.02, 40.5, ["astro"]), ("munih", 48.15, 11.6, ["wildlife"]), ("fiji", -17.7, 178.0, [])]:
        await register(client, name)
        await _place(name, lat, lng, specialties=spec)
    await register(client, "gizlici")
    await _place("gizlici", 41.0, 39.72, public=False)

    turkey = "35,36,45,42"
    far = (await client.get(f"/map/photographers?bbox={turkey}&zoom=4")).json()
    assert far["total"] == 3  # gizli profil yok
    assert far["clusters"] and far["clusters"][0]["count"] == 3 and far["photographers"] == []

    near = (await client.get(f"/map/photographers?bbox={turkey}&zoom=14")).json()
    assert sorted(p["user"]["username"] for p in near["photographers"]) == ["rize", "trabzon1", "trabzon2"]
    mid = (await client.get(f"/map/photographers?bbox={turkey}&zoom=9")).json()
    assert [c["count"] for c in mid["clusters"]] == [2] and [p["user"]["username"] for p in mid["photographers"]] == ["rize"]

    astro = (await client.get(f"/map/photographers?bbox={turkey}&zoom=14&specialty=astro")).json()
    assert sorted(p["user"]["username"] for p in astro["photographers"]) == ["rize", "trabzon1"]

    pacific = (await client.get("/map/photographers?bbox=170,-30,-170,0&zoom=14")).json()  # 180. meridyeni geçen görünüm
    assert [p["user"]["username"] for p in pacific["photographers"]] == ["fiji"]
    assert (await client.get("/map/photographers?bbox=1,2,3")).json()["error"]["code"] == "invalid_bbox"

    # Fotoğraf katmanı yalnızca bilinçli eklenmiş konumları gösterir
    h, _ = await register(client, "manzaraci")
    with_loc = await upload_photo(client, h, fake_storage, title="Uzungöl")
    await client.patch(f"/photos/{with_loc}", headers=h, json={"location": {"latitude": 40.62, "longitude": 40.3, "name": "Uzungöl"}})
    await upload_photo(client, h, fake_storage, title="Konumsuz")
    pm = (await client.get(f"/map/photos?bbox={turkey}&zoom=14")).json()
    assert pm["total"] == 1 and pm["photos"][0]["title"] == "Uzungöl" and pm["photos"][0]["thumb_url"]


async def test_guides_localized(client):
    from app.content.guides import GUIDES

    tr = (await client.get("/guides")).json()
    assert len(tr) == len(GUIDES) == 9 and tr[0]["title"] == "Samanyolu" and "settings" not in tr[0]
    en = (await client.get("/guides/milky-way", headers={"Accept-Language": "en"})).json()
    assert en["title"] == "Milky Way" and en["calculator"] == "npf" and en["planner"] is True and len(en["tips"]) >= 3
    assert (await client.get("/guides/yok")).status_code == 404
    # Her rehber iki dilde de tüm alanları içermeli
    for g in GUIDES:
        for loc in ("tr", "en"):
            t = g[loc]
            assert set(t["settings"]) == {"mode", "aperture", "shutter", "iso", "focus", "white_balance", "other"}, (g["slug"], loc)
            assert t["tips"] and t["mistakes"] and len(t["tips"]) == len(g["tr"]["tips"])


async def test_user_search_ranks_prefix_and_hides_blocked(client):
    me, _ = await register(client, "arayan")
    await register(client, "deniz.kaya")
    await register(client, "kayadeniz")
    other, _ = await register(client, "engelleyen")
    await client.patch("/me", headers=other, json={"display_name": "Deniz Engel"})

    names = [u["username"] for u in (await client.get("/users/search?q=deniz", headers=me)).json()]
    assert names[0] == "deniz.kaya" and set(names) == {"deniz.kaya", "kayadeniz", "engelleyen"}
    assert [u["username"] for u in (await client.get("/users/search?q=@KAYA")).json()] == ["kayadeniz", "deniz.kaya"]
    # Joker karakterler düz metin sayılır
    assert (await client.get("/users/search?q=%25")).json() == []

    await client.post("/users/arayan/block", headers=other)
    names = [u["username"] for u in (await client.get("/users/search?q=deniz", headers=me)).json()]
    assert "engelleyen" not in names
    assert (await client.get("/users/search?q=")).status_code == 422



async def test_follow_lists_search_and_remove_follower(client):
    me, _ = await register(client, "listeci")
    for name in ("ayse.kaya", "burak", "kaya.can"):
        h, _ = await register(client, name)
        await client.post("/users/listeci/follow", headers=h)
        await client.post(f"/users/{name}/follow", headers=me)
    names = lambda r: sorted(u["username"] for u in r.json()["items"])
    assert names(await client.get("/users/listeci/followers?q=kaya")) == ["ayse.kaya", "kaya.can"]
    assert names(await client.get("/users/listeci/following?q=BUR")) == ["burak"]

    assert (await client.delete("/me/followers/burak", headers=me)).status_code == 204
    assert names(await client.get("/users/listeci/followers")) == ["ayse.kaya", "kaya.can"]
    # Ben hâlâ onu takip ediyorum; yalnızca onun beni takibi kalktı
    assert "burak" in names(await client.get("/users/listeci/following"))
    assert (await client.delete("/me/followers/burak")).status_code == 401
