"""Revizyon 5: akış kartında yorum bilgisi, kayıt sonrası tanıtım, mesaj isteği bildirimi."""
import pytest

from tests.test_api import register
from tests.test_phase1_complete import upload_photo

pytestmark = pytest.mark.asyncio


async def test_feed_card_comment_info(client, fake_storage):
    owner, _ = await register(client, "sahip5")
    fan, _ = await register(client, "hayran5")
    await client.post("/users/sahip5/follow", headers=fan)
    pid = await upload_photo(client, owner, fake_storage)

    card = (await client.get("/feed", headers=fan)).json()["items"][0]
    assert card["comment_count"] == 0 and card["last_comment"] is None and card["comments_off"] is False

    first = (await client.post(f"/photos/{pid}/comments", headers=fan, json={"body": "İlk!"})).json()
    await client.post(f"/photos/{pid}/comments", headers=owner, json={"body": "Teşekkürler", "parent_id": first["id"]})
    await client.post(f"/photos/{pid}/comments", headers=fan, json={"body": "Işık harika olmuş"})
    card = (await client.get("/feed", headers=fan)).json()["items"][0]
    # Cevaplar sayıya dahil, önizleme en son üst düzey yorum
    assert card["comment_count"] == 3 and card["last_comment"] == {"username": "hayran5", "body": "Işık harika olmuş"}

    await client.patch(f"/photos/{pid}", headers=owner, json={"comment_policy": "off"})
    card = (await client.get("/feed", headers=fan)).json()["items"][0]
    assert card["comments_off"] is True and card["comment_count"] == 0 and card["last_comment"] is None


async def test_onboarding_flag_and_has_photos(client, fake_storage):
    h, _ = await register(client, "yeni5")
    me = (await client.get("/me", headers=h)).json()
    assert me["onboarding_done"] is False and me["has_photos"] is False
    await upload_photo(client, h, fake_storage)
    me = (await client.patch("/me", headers=h, json={"onboarding_done": True})).json()
    assert me["onboarding_done"] is True and me["has_photos"] is True


async def test_message_request_creates_notification(client):
    a, _ = await register(client, "yazan5")
    b, _ = await register(client, "alan5")
    r = await client.post("/conversations", headers=a, json={"username": "alan5", "body": "Merhaba!"})
    assert r.status_code == 201, r.text
    items = (await client.get("/notifications", headers=b)).json()["items"]
    req = [n for n in items if n["type"] == "message_request"]
    assert len(req) == 1 and req[0]["data"]["conversation_id"] == r.json()["id"] and req[0]["actor"]["username"] == "yazan5"
    # İkinci mesaj yeni istek bildirimi üretmez
    await client.post("/conversations", headers=a, json={"username": "alan5", "body": "Orada mısın?"})
    items = (await client.get("/notifications", headers=b)).json()["items"]
    assert len([n for n in items if n["type"] == "message_request"]) == 1
