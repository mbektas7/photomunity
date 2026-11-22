"""Revizyon 4: fotoğraf yorumları ve yorum ayarı; mesajlarda cevap, tepki, görsel ve GIF; yorum/mesaj şikâyeti."""
import pytest

from app.services import giphy
from tests.conftest import make_jpeg
from tests.test_admin import make_admin
from tests.test_api import register
from tests.test_phase1_complete import upload_photo

pytestmark = pytest.mark.asyncio


async def test_comments_replies_quotes_and_policy(client, fake_storage):
    owner, _ = await register(client, "fotografci")
    fan, _ = await register(client, "hayran")
    other, _ = await register(client, "yabanci")
    pid = await upload_photo(client, owner, fake_storage)

    d = (await client.get(f"/photos/{pid}", headers=fan)).json()
    assert d["comment_policy"] == "everyone" and d["can_comment"] is True and d["comment_count"] == 0
    assert (await client.get(f"/photos/{pid}")).json()["can_comment"] is False  # giriş yapmamış

    c1 = (await client.post(f"/photos/{pid}/comments", headers=fan, json={"body": "Çekirdek çok net!"})).json()
    reply = await client.post(f"/photos/{pid}/comments", headers=owner, json={"body": "Tek kare, 20 sn.", "parent_id": c1["id"]})
    assert reply.status_code == 201 and reply.json()["by_photo_owner"] and reply.json()["parent_id"] == c1["id"]
    # Cevaba cevap aynı üst yoruma bağlanır; alıntı içeriği döner
    r2 = (await client.post(f"/photos/{pid}/comments", headers=other, json={
        "body": "14 mm ile mi?", "parent_id": reply.json()["id"], "quote_id": reply.json()["id"]})).json()
    assert r2["parent_id"] == c1["id"] and r2["quote"]["body"] == "Tek kare, 20 sn." and r2["quote"]["user"]["username"] == "fotografci"

    page = (await client.get(f"/photos/{pid}/comments", headers=fan)).json()
    assert page["total"] == 3 and [c["id"] for c in page["items"]] == [c1["id"]] and page["items"][0]["reply_count"] == 2
    replies = (await client.get(f"/comments/{c1['id']}/replies")).json()
    assert [r["body"] for r in replies] == ["Tek kare, 20 sn.", "14 mm ile mi?"]
    assert page["items"][0]["can_delete"] is True  # yazan

    # Bildirimler: fotoğraf sahibine yorum, cevaplanan kişiye cevap
    types = [n["type"] for n in (await client.get("/notifications", headers=owner)).json()["items"]]
    assert "photo_comment" in types
    assert "comment_reply" in [n["type"] for n in (await client.get("/notifications", headers=fan)).json()["items"]]

    # Yalnız takipçiler
    assert (await client.patch(f"/photos/{pid}", headers=owner, json={"comment_policy": "followers"})).json()["comment_policy"] == "followers"
    denied = await client.post(f"/photos/{pid}/comments", headers=other, json={"body": "selam"})
    assert denied.status_code == 403 and denied.json()["error"]["code"] == "comments_not_allowed"
    await client.post("/users/fotografci/follow", headers=other)
    assert (await client.post(f"/photos/{pid}/comments", headers=other, json={"body": "artık takipteyim"})).status_code == 201

    # Kapalı: liste boş, yorumlar silinmez; açınca geri gelir
    await client.patch(f"/photos/{pid}", headers=owner, json={"comment_policy": "off"})
    assert (await client.get(f"/photos/{pid}/comments", headers=fan)).json()["items"] == []
    assert (await client.get(f"/photos/{pid}", headers=owner)).json()["can_comment"] is False
    await client.patch(f"/photos/{pid}", headers=owner, json={"comment_policy": "everyone"})
    assert (await client.get(f"/photos/{pid}/comments", headers=fan)).json()["total"] == 4

    # Silme: başkası silemez; fotoğraf sahibi silebilir, cevaplar da kaybolur
    assert (await client.delete(f"/comments/{c1['id']}", headers=other)).status_code == 403
    assert (await client.delete(f"/comments/{c1['id']}", headers=owner)).status_code == 204
    after = (await client.get(f"/photos/{pid}/comments", headers=fan)).json()
    assert after["total"] == 1 and [c["body"] for c in after["items"]] == ["artık takipteyim"]


async def test_message_reply_reaction_image_and_gif(client, fake_storage, monkeypatch):
    a, _ = await register(client, "gonderen")
    b, _ = await register(client, "alici")
    cid = (await client.post("/conversations", headers=a, json={"username": "alici", "body": "Işık 6'da güzel olur"})).json()["id"]
    first = (await client.get(f"/conversations/{cid}/messages", headers=b)).json()["items"][0]

    # Alıntıyla cevap
    r = (await client.post(f"/conversations/{cid}/messages", headers=b, json={"body": "Tamamdır", "reply_to_id": first["id"]})).json()
    assert r["reply_to"] == {"id": first["id"], "sender_id": first["sender_id"], "kind": "text", "preview": "Işık 6'da güzel olur"}

    # Tepki: kişi başına bir tane, değiştirilebilir, kaldırılabilir
    url = f"/conversations/{cid}/messages/{first['id']}/reaction"
    assert (await client.put(url, headers=b, json={"emoji": "❤️"})).json()[0]["emoji"] == "❤️"
    assert [x["emoji"] for x in (await client.put(url, headers=b, json={"emoji": "🔥"})).json()] == ["🔥"]
    await client.put(url, headers=a, json={"emoji": "👍"})
    msgs = (await client.get(f"/conversations/{cid}/messages", headers=a)).json()["items"]
    assert sorted(x["emoji"] for x in msgs[0]["reactions"]) == ["👍", "🔥"]
    assert (await client.delete(url, headers=b)).json() == [{"user_id": msgs[0]["reactions"][1]["user_id"], "emoji": "👍"}]

    # Galeriden görsel: kırpılmaz, WebP'ye çevrilir, yükleme dosyası silinir
    me = (await client.get("/me", headers=a)).json()
    key = f"uploads/{me['id']}/gallery.jpg"
    fake_storage[key] = make_jpeg(1600, 1200)
    img = await client.post(f"/conversations/{cid}/messages", headers=a, json={"image_key": key})
    assert img.status_code == 201, img.text
    assert img.json()["image"]["width"] == 1600 and img.json()["image"]["height"] == 1200
    assert key not in fake_storage and any(k.startswith(f"photos/messages/{cid}/") for k in fake_storage)
    bad = await client.post(f"/conversations/{cid}/messages", headers=a, json={"image_key": f"uploads/{first['sender_id']}x/a.jpg"})
    assert bad.status_code == 400

    # GIF: kimlikten doğrulanır
    async def fake_fetch(gif_id, kind):
        return {"id": gif_id, "kind": kind, "url": f"https://media.giphy.com/media/{gif_id}/200w.gif", "width": 200, "height": 150}
    monkeypatch.setattr(giphy, "fetch", fake_fetch)
    g = (await client.post(f"/conversations/{cid}/messages", headers=a, json={"gif": {"id": "abc123", "kind": "sticker"}})).json()
    assert g["gif"]["kind"] == "sticker" and g["gif"]["url"].endswith("200w.gif")
    reply_to_gif = (await client.post(f"/conversations/{cid}/messages", headers=b, json={"body": "😂", "reply_to_id": g["id"]})).json()
    assert reply_to_gif["reply_to"]["kind"] == "gif"

    # Anahtar yoksa GIF araması kapalı
    nogif = await client.get("/gifs?q=kedi", headers=a)
    assert nogif.status_code == 503 and nogif.json()["error"]["code"] == "gifs_unavailable"


async def test_report_comment_and_message_then_admin_removes(client, fake_storage):
    owner, _ = await register(client, "sahip")
    troll, _ = await register(client, "trol")
    admin, _ = await register(client, "yonetici")
    await make_admin("yonetici")
    pid = await upload_photo(client, owner, fake_storage)
    c = (await client.post(f"/photos/{pid}/comments", headers=troll, json={"body": "kötü yorum"})).json()
    assert (await client.post("/reports", headers=owner, json={"target_type": "comment", "target_id": c["id"], "reason": "harassment"})).status_code == 201

    cid = (await client.post("/conversations", headers=troll, json={"username": "sahip", "body": "rahatsız edici mesaj"})).json()["id"]
    mid = (await client.get(f"/conversations/{cid}/messages", headers=owner)).json()["items"][0]["id"]
    # Kendi mesajını ya da sohbetin dışındaki biri şikâyet edemez
    assert (await client.post("/reports", headers=troll, json={"target_type": "message", "target_id": mid, "reason": "spam"})).status_code == 404
    assert (await client.post("/reports", headers=owner, json={"target_type": "message", "target_id": mid, "reason": "harassment"})).status_code == 201

    groups = (await client.get("/admin/report-groups", headers=admin)).json()
    by = {g["target_type"]: g for g in groups}
    assert by["comment"]["content"]["body"] == "kötü yorum" and by["comment"]["owner"]["username"] == "trol"
    assert by["message"]["content"]["body"] == "rahatsız edici mesaj"
    for tt, tid in (("comment", c["id"]), ("message", mid)):
        r = await client.post("/admin/report-groups/resolve", headers=admin, json={"target_type": tt, "target_id": tid, "action": "remove_content"})
        assert r.status_code == 204
    assert (await client.get(f"/photos/{pid}/comments", headers=owner)).json()["total"] == 0
    assert (await client.get(f"/conversations/{cid}/messages", headers=owner)).json()["items"][0]["body"] is None
