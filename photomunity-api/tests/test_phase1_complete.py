import io

import pytest
from PIL import Image

from app.core.config import get_settings
from app.services import photo_pipeline
from app.services.moderation import ModerationResult
from app.services.ratelimit import limiter
from tests.conftest import make_jpeg
from tests.test_api import register

pytestmark = pytest.mark.asyncio


async def upload_photo(client, headers, store, data=None, title="Kare"):
    data = data or make_jpeg()
    up = (await client.post("/photos/upload-url", headers=headers, json={"content_type": "image/jpeg", "size_bytes": len(data)})).json()
    store[up["fields"]["key"]] = data
    await client.post(f"/photos/{up['photo_id']}/complete", headers=headers, json={"title": title})
    return up["photo_id"]


async def notifications(client, headers):
    return (await client.get("/notifications", headers=headers)).json()


async def test_follow_and_like_notifications(client, fake_storage):
    a, _ = await register(client, "ayse")
    b, _ = await register(client, "burak")

    await client.post("/users/ayse/follow", headers=b)
    await client.delete("/users/ayse/follow", headers=b)
    await client.post("/users/ayse/follow", headers=b)  # tekrar takip, tekrar bildirim üretmez
    page = await notifications(client, a)
    assert [n["type"] for n in page["items"]] == ["new_follower"]
    assert page["unread_count"] == 1
    assert page["items"][0]["actor"]["username"] == "burak"
    assert page["items"][0]["text"] == "Burak seni takip etmeye başladı."

    en = (await client.get("/notifications", headers={**a, "Accept-Language": "en"})).json()
    assert en["items"][0]["text"] == "Burak started following you."

    photo_id = await upload_photo(client, a, fake_storage)
    page = await notifications(client, a)
    assert page["items"][0]["type"] == "photo_published"
    assert page["items"][0]["photo"]["thumb_url"].endswith("thumb.webp")

    await client.post(f"/photos/{photo_id}/like", headers=b)
    await client.delete(f"/photos/{photo_id}/like", headers=b)
    await client.post(f"/photos/{photo_id}/like", headers=b)
    await client.post(f"/photos/{photo_id}/like", headers=a)  # kendi beğenisi bildirim üretmez
    types = [n["type"] for n in (await notifications(client, a))["items"]]
    assert types.count("photo_liked") == 1

    assert (await client.get("/notifications/unread-count", headers=a)).json()["count"] == 3
    await client.post("/notifications/read", headers=a, json={})
    assert (await client.get("/notifications/unread-count", headers=a)).json()["count"] == 0


async def test_notification_settings_and_devices(client):
    a, _ = await register(client, "cem")
    s = (await client.get("/me/notification-settings", headers=a)).json()
    assert s["push"]["new_follower"] is True and s["push"]["photo_liked"] is False
    s = (await client.patch("/me/notification-settings", headers=a, json={"push": {"photo_liked": True, "bogus": True}})).json()
    assert s["push"]["photo_liked"] is True and "bogus" not in s["push"]

    b, _ = await register(client, "deniz")
    token = "fcm-token-1234567890"
    assert (await client.post("/devices", headers=a, json={"token": token, "platform": "ios"})).status_code == 204
    # Aynı cihazda başka hesaba geçilirse token o hesaba taşınır
    assert (await client.post("/devices", headers=b, json={"token": token, "platform": "ios"})).status_code == 204
    assert (await client.delete(f"/devices/{token}", headers=b)).status_code == 204


def _png(w, h):
    buf = io.BytesIO()
    Image.new("RGB", (w, h), (120, 90, 200)).save(buf, "PNG")
    return buf.getvalue()


async def test_avatar_and_cover_upload(client, fake_storage):
    a, me = await register(client, "fotograf.ci")
    uid = me["user"]["id"]

    async def put(kind, data):
        up = (await client.post("/me/images/upload-url", headers=a, json={"kind": kind, "content_type": "image/png", "size_bytes": len(data)})).json()
        key = up["fields"]["key"]
        assert key.startswith(f"uploads/{uid}/")
        fake_storage[key] = data
        return await client.post("/me/images/complete", headers=a, json={"kind": kind, "key": key})

    r = await put("avatar", _png(900, 600))
    assert r.status_code == 200, r.text
    avatar = r.json()["avatar_url"]
    assert "/photos/profile/" in avatar and avatar.endswith(".webp")
    stored = [k for k in fake_storage if k.startswith(f"photos/profile/{uid}/avatar-")]
    assert len(stored) == 1 and Image.open(io.BytesIO(fake_storage[stored[0]])).size == (400, 400)
    assert not [k for k in fake_storage if k.startswith("uploads/")]  # geçici dosya silindi

    r = await put("avatar", _png(1000, 1000))  # yenisi eskisini siler
    assert len([k for k in fake_storage if k.startswith(f"photos/profile/{uid}/avatar-")]) == 1

    small = await put("avatar", _png(120, 120))
    assert small.status_code == 422 and small.json()["error"]["code"] == "image_too_small"

    cover = await put("cover", _png(2400, 1600))
    assert cover.status_code == 200 and cover.json()["cover_url"]

    bad = await client.post("/me/images/complete", headers=a, json={"kind": "avatar", "key": "uploads/someone-else/x.png"})
    assert bad.status_code == 400 and bad.json()["error"]["code"] == "invalid_key"

    gone = await client.delete("/me/images/avatar", headers=a)
    assert gone.json()["avatar_url"] is None


async def test_reports_auto_hide_and_admin_resolve(client, fake_storage, monkeypatch):
    monkeypatch.setattr(get_settings(), "report_auto_hide_threshold", 3)
    owner, _ = await register(client, "sahip")
    photo_id = await upload_photo(client, owner, fake_storage)

    reporters = [(await register(client, f"izleyici{i}"))[0] for i in range(3)]
    for h in reporters[:2]:
        assert (await client.post("/reports", headers=h, json={"target_type": "photo", "target_id": photo_id, "reason": "spam"})).status_code == 201
    dup = await client.post("/reports", headers=reporters[0], json={"target_type": "photo", "target_id": photo_id, "reason": "spam"})
    assert dup.status_code == 409
    assert len((await client.get("/explore")).json()["items"]) == 1

    await client.post("/reports", headers=reporters[2], json={"target_type": "photo", "target_id": photo_id, "reason": "nudity"})
    assert len((await client.get("/explore")).json()["items"]) == 0
    assert (await client.get(f"/photos/{photo_id}", headers=reporters[0])).status_code == 404
    assert (await client.get(f"/photos/{photo_id}", headers=owner)).status_code == 200  # sahibi görür

    # Yönetici şikayetleri reddeder, fotoğraf geri açılır
    admin, admin_body = await register(client, "yonetici")
    assert (await client.get("/admin/reports", headers=admin)).status_code == 403
    from app.core.database import SessionLocal
    from app.models import User
    import uuid
    async with SessionLocal() as db:
        (await db.get(User, uuid.UUID(admin_body["user"]["id"]))).is_admin = True
        await db.commit()
    reports = (await client.get("/admin/reports", headers=admin)).json()
    assert len(reports) == 3
    await client.post(f"/admin/reports/{reports[0]['id']}/resolve", headers=admin, json={"action": "dismiss"})
    assert (await client.get("/admin/reports", headers=admin)).json() == []
    assert len((await client.get("/explore")).json()["items"]) == 1


async def test_rate_limit_login(client, monkeypatch):
    monkeypatch.setattr(get_settings(), "rate_limit_enabled", True)
    limiter.reset()
    await register(client, "hizli")
    codes = [(await client.post("/auth/login", json={"email": "hizli@example.com", "password": "yanlis-sifre"})).status_code for _ in range(22)]
    assert codes[:20] == [401] * 20 and codes[20:] == [429, 429]
    limiter.reset()


async def test_moderation_rejects_unsafe_photo(client, fake_storage, monkeypatch):
    monkeypatch.setattr(photo_pipeline, "moderate", lambda data: ModerationResult(safe=False, labels=["Explicit Nudity"]))
    a, _ = await register(client, "mod")
    photo_id = await upload_photo(client, a, fake_storage)
    detail = (await client.get(f"/photos/{photo_id}", headers=a)).json()
    assert detail["status"] == "rejected" and detail["rejection"][0]["code"] == "inappropriate_content"
    assert (await notifications(client, a))["items"][0]["type"] == "photo_rejected"
