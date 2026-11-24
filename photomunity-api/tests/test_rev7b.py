"""Revizyon 7b: paylaşılan çekim planları (katılım, hatırlatma) ve ekipman keşfinde etiket filtresi."""
from datetime import timedelta

import pytest

import app.worker as worker
from tests.test_api import register
from tests.test_phase1_complete import notifications, upload_photo
from tests.test_phase2 import T0
from tests.test_rev7 import clock, gear_jpeg, types  # noqa: F401 — clock fixture

pytestmark = pytest.mark.asyncio


def plan_body(target, **kw):
    return {"kind": "milkyway", "latitude": 40.63, "longitude": 39.41, "place_name": "Zigana Geçidi",
            "target_at": target.isoformat(), "remind": True, "weather_alert": False, **kw}


async def test_shared_plans_visibility_join_and_unshare(client, clock):
    owner, _ = await register(client, "gezgin")
    fan, _ = await register(client, "takipci")
    stranger, _ = await register(client, "yabanci")
    target = T0 + timedelta(hours=30)

    r = await client.post("/me/plans", headers=owner, json=plan_body(target))
    assert r.status_code == 201 and r.json()["shared"] is False and r.json()["join_count"] == 0 and r.json()["joiners"] == []
    private_pid = r.json()["id"]
    r = await client.post("/me/plans", headers=owner, json=plan_body(target + timedelta(hours=1), shared=True, title="Perseid"))
    pid = r.json()["id"]
    assert r.json()["shared"] is True

    await client.post("/users/gezgin/follow", headers=fan)
    page = (await client.get("/plans/shared", headers=fan)).json()
    assert [p["id"] for p in page["items"]] == [pid] and page["next_cursor"] is None
    item = page["items"][0]
    assert item["owner"]["username"] == "gezgin" and item["joined"] is False and item["status"] == "upcoming"
    assert item["title"] == "Perseid" and item["join_count"] == 0 and "remind" not in item
    # Takip etmeyen listede görmez; kendi planlarım listede yok
    assert (await client.get("/plans/shared", headers=stranger)).json()["items"] == []
    assert (await client.get("/plans/shared", headers=owner)).json()["items"] == []
    assert (await client.get("/plans/shared")).status_code == 401

    # Ayrıntı: paylaşılmamış plan sahibinden başkasına 404
    assert (await client.get(f"/plans/{private_pid}", headers=fan)).status_code == 404
    assert (await client.get(f"/plans/{private_pid}", headers=owner)).status_code == 200
    assert (await client.get(f"/plans/{pid}", headers=stranger)).status_code == 200  # açık profil

    # Kapalı profil: takip etmeyen göremez, takipçi görür
    await client.patch("/me", headers=owner, json={"is_public": False})
    assert (await client.get(f"/plans/{pid}", headers=stranger)).status_code == 404
    assert (await client.post(f"/plans/{pid}/join", headers=stranger)).status_code == 404
    assert (await client.get(f"/plans/{pid}", headers=fan)).status_code == 200

    # Katılım
    assert (await client.post(f"/plans/{pid}/join", headers=owner)).json()["error"]["code"] == "cannot_join_own"
    assert (await client.post(f"/plans/{pid}/join", headers=owner)).status_code == 403
    r = await client.post(f"/plans/{private_pid}/join", headers=fan)
    assert r.status_code == 409 and r.json()["error"]["code"] == "plan_not_shared"
    r = await client.post(f"/plans/{pid}/join", headers=fan)
    assert r.status_code == 200 and r.json()["joined"] is True and r.json()["join_count"] == 1
    assert r.json()["joiners"][0]["username"] == "takipci"
    assert (await client.post(f"/plans/{pid}/join", headers=fan)).json()["join_count"] == 1  # idempotent
    page = await notifications(client, owner)
    assert types(page).count("plan_join") == 1 and types(page)[0] == "plan_join"
    n = page["items"][0]
    assert n["text"] == "Takipci Perseid çekimine katılıyor." and n["data"]["plan_id"] == pid
    assert n["data"]["place"] == "Zigana Geçidi" and n["actor"]["username"] == "takipci"
    en = (await client.get("/notifications", headers={**owner, "Accept-Language": "en"})).json()
    assert en["items"][0]["text"] == "Takipci is joining your Perseid shoot."
    mine = (await client.get(f"/me/plans/{pid}", headers=owner)).json()
    assert mine["join_count"] == 1 and mine["joiners"][0]["username"] == "takipci"
    assert (await client.get("/plans/shared", headers=fan)).json()["items"][0]["joined"] is True

    # Ayrılma ve tekrar katılma
    assert (await client.delete(f"/plans/{pid}/join", headers=fan)).status_code == 204
    assert (await client.get(f"/plans/{pid}", headers=fan)).json()["join_count"] == 0
    await client.post(f"/plans/{pid}/join", headers=fan)

    # Paylaşım kapatılınca katılımlar silinir, plan başkasına görünmez
    upd = (await client.patch(f"/me/plans/{pid}", headers=owner, json={"shared": False})).json()
    assert upd["shared"] is False and upd["join_count"] == 0
    assert (await client.get(f"/plans/{pid}", headers=fan)).status_code == 404
    await client.patch(f"/me/plans/{pid}", headers=owner, json={"shared": True})
    assert (await client.get(f"/plans/{pid}", headers=fan)).json()["join_count"] == 0

    # Engel iki yönlü: engellenen ya da engelleyen göremez
    await client.post("/users/takipci/block", headers=owner)
    assert (await client.get(f"/plans/{pid}", headers=fan)).status_code == 404
    assert (await client.get("/plans/shared", headers=fan)).json()["items"] == []

    # Plan silinince katılımlar da gider
    await client.delete("/users/takipci/block", headers=owner)
    await client.post("/users/gezgin/follow", headers=fan)
    await client.post(f"/plans/{pid}/join", headers=fan)
    assert (await client.delete(f"/me/plans/{pid}", headers=owner)).status_code == 204
    assert (await client.get(f"/plans/{pid}", headers=fan)).status_code == 404


async def test_shared_plan_past_and_paging(client, clock):
    owner, _ = await register(client, "gezgin")
    fan, _ = await register(client, "takipci")
    await client.post("/users/gezgin/follow", headers=fan)
    ids = []
    for h in (50, 10, 30):
        ids.append((await client.post("/me/plans", headers=owner, json=plan_body(T0 + timedelta(hours=h), shared=True))).json()["id"])
    first = (await client.get("/plans/shared?limit=2", headers=fan)).json()
    assert [p["id"] for p in first["items"]] == [ids[1], ids[2]] and first["next_cursor"] == "2"
    second = (await client.get(f"/plans/shared?limit=2&cursor={first['next_cursor']}", headers=fan)).json()
    assert [p["id"] for p in second["items"]] == [ids[0]] and second["next_cursor"] is None
    assert (await client.get("/plans/shared?limit=51", headers=fan)).status_code == 422

    # Zamanı geçen plan: listede yok, ayrıntıda "past", katılınamaz
    clock.set(T0 + timedelta(hours=11))
    assert ids[1] not in [p["id"] for p in (await client.get("/plans/shared", headers=fan)).json()["items"]]
    assert (await client.get(f"/plans/{ids[1]}", headers=fan)).json()["status"] == "past"
    r = await client.post(f"/plans/{ids[1]}/join", headers=fan)
    assert r.status_code == 409 and r.json()["error"]["code"] == "plan_past"


async def test_joiner_reminders(client, clock, monkeypatch):
    owner, _ = await register(client, "gezgin")
    fan, _ = await register(client, "takipci")
    late, _ = await register(client, "gecikmeli")
    target = T0 + timedelta(hours=30)
    pid = (await client.post("/me/plans", headers=owner, json=plan_body(target, shared=True, weather_alert=True))).json()["id"]
    await client.post("/users/gezgin/follow", headers=fan)
    await client.post(f"/plans/{pid}/join", headers=fan)

    clock.set(target - timedelta(hours=23))
    await worker.reminder_tick({})
    await worker.reminder_tick({})
    for h in (owner, fan):
        page = await notifications(client, h)
        assert types(page).count("plan_reminder") == 1
    page = await notifications(client, fan)
    assert page["items"][0]["data"]["hours"] == 24 and page["items"][0]["data"]["plan_id"] == pid
    assert page["items"][0]["text"] == "Hatırlatma: Samanyolu çekimine 24 saat kaldı."

    # 24 saatten az kala katılan günlük hatırlatmayı almaz, 2 saatlik hatırlatmayı alır
    await client.post(f"/plans/{pid}/join", headers=late)
    await worker.reminder_tick({})
    assert "plan_reminder" not in types(await notifications(client, late))
    clock.set(target - timedelta(minutes=90))
    await worker.reminder_tick({})
    await worker.reminder_tick({})
    for h, total in ((owner, 2), (fan, 2), (late, 1)):
        page = await notifications(client, h)
        assert types(page).count("plan_reminder") == total and page["items"][0]["data"]["hours"] == 2

    # Katılımcılar hava uyarısı almaz
    from tests.test_rev7 import fake_http
    clock.set(target - timedelta(hours=20))
    fake_http(monkeypatch, {"hourly": {"time": [target.strftime("%Y-%m-%dT%H:00")], "cloud_cover": [90]}})
    await worker.plan_weather_tick({})
    assert "plan_weather" in types(await notifications(client, owner))
    assert "plan_weather" not in types(await notifications(client, fan))


async def test_gear_tag_filter_and_top_tags(client, fake_storage):
    a, _ = await register(client, "astro")
    b, _ = await register(client, "sokak")
    p1 = await upload_photo(client, a, fake_storage, data=gear_jpeg("ILCE-7M4", seed=1))
    p2 = await upload_photo(client, a, fake_storage, data=gear_jpeg("ILCE-7M4", seed=2))
    p3 = await upload_photo(client, b, fake_storage, data=gear_jpeg("ILCE-7M4", seed=3))
    p4 = await upload_photo(client, b, fake_storage, data=gear_jpeg("X-T5", seed=4))
    await client.patch(f"/photos/{p1}", headers=a, json={"tags": ["Astro", "milkyway"]})
    await client.patch(f"/photos/{p2}", headers=a, json={"tags": ["astro", "gece"]})
    await client.patch(f"/photos/{p3}", headers=b, json={"tags": ["#ASTRO", "sokak", "gece"]})
    await client.patch(f"/photos/{p4}", headers=b, json={"tags": ["astro"]})

    got = (await client.get("/gear/photos", params={"camera": "ILCE-7M4", "tag": " ASTRO "})).json()
    assert [p["id"] for p in got["items"]] == [p3, p2, p1] and got["next_cursor"] is None
    page1 = (await client.get("/gear/photos", params={"camera": "ILCE-7M4", "tag": "astro", "limit": 2})).json()
    assert [p["id"] for p in page1["items"]] == [p3, p2] and page1["next_cursor"] == "2"
    page2 = (await client.get("/gear/photos", params={"camera": "ILCE-7M4", "tag": "astro", "cursor": "2"})).json()
    assert [p["id"] for p in page2["items"]] == [p1] and page2["next_cursor"] is None
    assert [p["id"] for p in (await client.get("/gear/photos", params={"camera": "ILCE-7M4", "tag": "gece"})).json()["items"]] == [p3, p2]
    assert (await client.get("/gear/photos", params={"camera": "ILCE-7M4", "tag": "astr"})).json()["items"] == []
    pop = (await client.get("/gear/photos", params={"camera": "ILCE-7M4", "tag": "milkyway", "sort": "popular"})).json()
    assert [p["id"] for p in pop["items"]] == [p1]

    stats = (await client.get("/gear/stats", params={"camera": "ilce-7m4"})).json()
    assert stats["top_tags"][:2] == [{"tag": "astro", "count": 3}, {"tag": "gece", "count": 2}]
    assert {t["tag"] for t in stats["top_tags"]} == {"astro", "gece", "milkyway", "sokak"}
    assert (await client.get("/gear/stats", params={"camera": "X-T5"})).json()["top_tags"] == [{"tag": "astro", "count": 1}]
