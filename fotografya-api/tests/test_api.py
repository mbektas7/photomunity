import pytest
from PIL import ExifTags, Image

from tests.conftest import make_jpeg

pytestmark = pytest.mark.asyncio


async def register(client, username, email=None):
    r = await client.post("/auth/register", json={
        "email": email or f"{username}@example.com", "password": "Sifre1234!", "username": username,
        "display_name": username.title()})
    assert r.status_code == 201, r.text
    return {"Authorization": f"Bearer {r.json()['tokens']['access_token']}"}, r.json()


async def test_auth_flow(client):
    headers, body = await register(client, "mirac")
    assert body["user"]["email_verified"] is False

    dup = await client.post("/auth/register", json={
        "email": "MIRAC@example.com", "password": "Sifre1234!", "username": "baska", "display_name": "x"})
    assert dup.status_code == 409 and dup.json()["error"]["code"] == "email_taken"

    bad = await client.post("/auth/login", json={"email": "mirac@example.com", "password": "yanlis-sifre"},
                            headers={"Accept-Language": "en"})
    assert bad.status_code == 401 and bad.json()["error"]["message"] == "Incorrect email or password."

    ok = await client.post("/auth/login", json={"email": "mirac@example.com", "password": "Sifre1234!"})
    refresh_token = ok.json()["tokens"]["refresh_token"]

    rotated = await client.post("/auth/refresh", json={"refresh_token": refresh_token})
    assert rotated.status_code == 200
    reused = await client.post("/auth/refresh", json={"refresh_token": refresh_token})
    assert reused.status_code == 401  # rotasyon + yeniden kullanım tespiti
    # yeniden kullanım tespiti diğer oturumu da kapatır
    again = await client.post("/auth/refresh", json={"refresh_token": rotated.json()["refresh_token"]})
    assert again.status_code == 401

    me = await client.get("/me", headers=headers)
    assert me.json()["username"] == "mirac"


async def test_profile_equipment_follow_privacy(client):
    a, _ = await register(client, "ayse")
    b, _ = await register(client, "burak")

    r = await client.patch("/me", headers=a, json={"bio": "Karadeniz", "is_public": False,
                                                   "latitude": 41.00271, "longitude": 39.71678, "country": "tr"})
    assert r.json()["latitude"] == 41.0 and r.json()["longitude"] == 39.7 and r.json()["country"] == "TR"

    eq = await client.put("/me/equipment", headers=a, json=[
        {"type": "body", "brand": "Sony", "model": "A7 IV"}, {"type": "lens", "brand": "Sigma", "model": "14mm f/1.4"}])
    assert len(eq.json()) == 2

    prof = await client.get("/users/ayse", headers=b)
    assert prof.json()["can_view_photos"] is False and len(prof.json()["equipment"]) == 2
    blocked = await client.get("/users/ayse/photos", headers=b)
    assert blocked.status_code == 403

    assert (await client.post("/users/ayse/follow", headers=b)).status_code == 204
    prof = await client.get("/users/ayse", headers=b)
    assert prof.json()["is_following"] and prof.json()["can_view_photos"] and prof.json()["followers_count"] == 1
    assert (await client.get("/users/ayse/photos", headers=b)).status_code == 200
    assert (await client.post("/users/burak/follow", headers=b)).status_code == 400


async def test_photo_upload_pipeline(client, fake_storage):
    a, _ = await register(client, "fotografci")
    b, _ = await register(client, "izleyici")
    await client.post("/users/fotografci/follow", headers=b)

    too_small = await client.post("/photos/upload-url", headers=a, json={"content_type": "image/jpeg", "size_bytes": 1000})
    assert too_small.status_code == 422 and too_small.json()["error"]["code"] == "file_too_small"

    exif = Image.Exif()
    exif[ExifTags.Base.Make] = "Canon"
    exif[ExifTags.Base.Model] = "EOS R6"
    sub = {}
    sub[ExifTags.Base.FNumber] = 1.8
    sub[ExifTags.Base.ISOSpeedRatings] = 3200
    sub[ExifTags.Base.ExposureTime] = 15.0
    gps = {}
    gps[ExifTags.GPS.GPSLatitudeRef], gps[ExifTags.GPS.GPSLatitude] = "N", (40.0, 30.0, 0.0)
    gps[ExifTags.GPS.GPSLongitudeRef], gps[ExifTags.GPS.GPSLongitude] = "E", (40.0, 0.0, 0.0)
    exif[ExifTags.IFD.Exif] = sub
    exif[ExifTags.IFD.GPSInfo] = gps
    data = make_jpeg(exif=exif)

    up = await client.post("/photos/upload-url", headers=a, json={"content_type": "image/jpeg", "size_bytes": len(data)})
    assert up.status_code == 201
    photo_id = up.json()["photo_id"]
    assert up.json()["fields"]["key"].startswith("originals/")
    fake_storage[up.json()["fields"]["key"]] = data  # istemcinin doğrudan yüklemesini taklit et

    done = await client.post(f"/photos/{photo_id}/complete", headers=a,
                             json={"title": "Uzungöl gecesi", "tags": ["#Astro", "samanyolu"]})
    assert done.status_code == 202

    detail = (await client.get(f"/photos/{photo_id}", headers=a)).json()
    assert detail["status"] == "published"
    assert detail["exif"]["camera_model"] == "EOS R6" and detail["exif"]["shutter_display"] == '15"'
    assert detail["suggested_location"]["latitude"] == 40.5  # GPS yalnızca sahibine öneri
    assert set(detail["images"]) == {"thumb", "feed", "full"} and detail["tags"] == ["astro", "samanyolu"]
    assert "gps_latitude" not in detail["exif"]

    # Türevlerde EXIF/GPS yok
    variant = fake_storage[f"photos/{detail['user']['id']}/{photo_id}/full.webp"]
    import io
    assert not Image.open(io.BytesIO(variant)).getexif()

    viewer_view = (await client.get(f"/photos/{photo_id}", headers=b)).json()
    assert viewer_view["suggested_location"] is None

    assert (await client.post(f"/photos/{photo_id}/like", headers=b)).status_code == 204
    assert (await client.post(f"/photos/{photo_id}/like", headers=b)).status_code == 204  # idempotent
    feed = (await client.get("/feed", headers=b)).json()
    assert feed["items"][0]["like_count"] == 1 and feed["items"][0]["liked_by_me"] is True

    explore = (await client.get("/explore")).json()
    assert len(explore["items"]) == 1


async def test_blurry_upload_rejected_with_reason(client, fake_storage):
    a, _ = await register(client, "bulanik")
    data = make_jpeg(blur=True)
    up = (await client.post("/photos/upload-url", headers=a,
                            json={"content_type": "image/jpeg", "size_bytes": max(len(data), 1_000_001)})).json()
    fake_storage[up["fields"]["key"]] = data
    await client.post(f"/photos/{up['photo_id']}/complete", headers=a, json={})
    detail = (await client.get(f"/photos/{up['photo_id']}", headers=a)).json()
    assert detail["status"] == "rejected"
    assert any(r["code"] == "too_blurry" and r["message"] == "Görsel bulanık görünüyor." for r in detail["rejection"])
    assert up["fields"]["key"] not in fake_storage  # reddedilen orijinal silindi
