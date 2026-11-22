"""Site yönetim paneli: yetki, şikâyet kararı, kullanıcı/fotoğraf/topluluk/yarışma işlemleri, duyuru ve işlem kaydı."""
import pytest
from sqlalchemy import update

from app.core.database import SessionLocal
from app.models import User
from tests.test_api import register
from tests.test_phase1_complete import notifications, upload_photo
from tests.test_phase2 import contest_body, make_community

pytestmark = pytest.mark.asyncio


async def make_admin(username):
    async with SessionLocal() as db:
        await db.execute(update(User).where(User.username == username).values(is_admin=True))
        await db.commit()


async def test_admin_panel_end_to_end(client, fake_storage, monkeypatch):
    monkeypatch.setattr("app.api.v1.admin.get_settings", lambda: type("S", (), {"admin_owner_username": "patron"})())
    boss, _ = await register(client, "patron")
    ayse, ayse_body = await register(client, "ayse")
    burak, _ = await register(client, "burak")
    cem, _ = await register(client, "cem")

    # Yönetici olmayan giremez; me çıktısı is_admin taşır
    assert (await client.get("/admin/stats", headers=ayse)).status_code == 403
    await make_admin("patron")
    assert (await client.get("/me", headers=boss)).json()["is_admin"] is True

    photo = await upload_photo(client, ayse, fake_storage, title="Yayla")
    s = (await client.get("/admin/stats", headers=boss)).json()
    assert s["users"]["total"] == 4 and s["photos"]["total"] == 1 and len(s["uploads"]) == 30

    # Şikâyet grubu: iki kişi, tek karar hepsini kapatır, not kayda geçer
    for h, reason in ((burak, "spam"), (cem, "nudity")):
        assert (await client.post("/reports", headers=h, json={"target_type": "photo", "target_id": photo, "reason": reason})).status_code == 201
    groups = (await client.get("/admin/report-groups", headers=boss)).json()
    assert len(groups) == 1 and len(groups[0]["reports"]) == 2 and groups[0]["owner"]["username"] == "ayse"
    assert set(groups[0]["reasons"]) == {"spam", "nudity"}
    r = await client.post("/admin/report-groups/resolve", headers=boss,
                          json={"target_type": "photo", "target_id": photo, "action": "hide_photo", "note": "Kural ihlali"})
    assert r.status_code == 204
    assert (await client.get("/admin/report-groups", headers=boss)).json() == []
    assert (await client.get(f"/photos/{photo}", headers=burak)).status_code == 404
    assert [p["id"] for p in (await client.get("/admin/photos?tab=hidden", headers=boss)).json()["items"]] == [photo]

    # Toplu: geri aç, sonra kalıcı sil
    assert (await client.post("/admin/photos/bulk", headers=boss, json={"ids": [photo], "action": "unhide"})).status_code == 204
    assert (await client.get(f"/photos/{photo}", headers=burak)).status_code == 200
    assert (await client.post("/admin/photos/bulk", headers=boss, json={"ids": [photo], "action": "delete"})).status_code == 204
    assert (await client.get(f"/photos/{photo}", headers=ayse)).status_code == 404

    # Kullanıcılar: arama, devre dışı bırakma oturumları kapatır, sahip devre dışı bırakılamaz
    found = (await client.get("/admin/users?q=bura", headers=boss)).json()
    assert found["total"] == 1 and found["items"][0]["username"] == "burak"
    bid = found["items"][0]["id"]
    assert (await client.post(f"/admin/users/{bid}/status", headers=boss, json={"active": False})).status_code == 204
    assert (await client.get("/me", headers=burak)).status_code == 401
    assert (await client.get("/admin/users?filter=disabled", headers=boss)).json()["total"] == 1
    me_id = (await client.get("/me", headers=boss)).json()["id"]
    assert (await client.post(f"/admin/users/{me_id}/status", headers=boss, json={"active": False})).status_code == 403
    detail = (await client.get(f"/admin/users/{ayse_body['user']['id']}", headers=boss)).json()
    assert detail["username"] == "ayse" and detail["providers"] == ["email"]

    # Topluluk: gizlenince herkese kapanır, sahiplik devredilir
    slug = await make_community(client, ayse)
    cid = (await client.get("/admin/communities", headers=boss)).json()["items"][0]["id"]
    contest = (await client.post(f"/communities/{slug}/contests", headers=ayse, json=contest_body("public"))).json()
    await client.post(f"/contests/{contest['id']}/publish", headers=ayse)
    assert (await client.post(f"/admin/communities/{cid}/hidden", headers=boss, json={"hidden": True})).status_code == 204
    assert (await client.get(f"/communities/{slug}", headers=cem)).status_code == 404
    assert slug not in [c["slug"] for c in (await client.get("/communities", headers=cem)).json()]
    assert (await client.get(f"/contests/{contest['id']}", headers=cem)).status_code == 404
    await client.post(f"/admin/communities/{cid}/hidden", headers=boss, json={"hidden": False})
    assert (await client.post(f"/admin/communities/{cid}/transfer", headers=boss, json={"username": "@cem"})).status_code == 204
    assert (await client.get(f"/communities/{slug}", headers=cem)).json()["my_role"] == "owner"

    # Yarışma: iptal edilince gizlenir
    rows = (await client.get("/admin/contests?tab=all", headers=boss)).json()["items"]
    assert rows[0]["community"]["slug"] == slug
    assert (await client.post(f"/admin/contests/{contest['id']}/cancel", headers=boss, json={"note": "Dolandırıcılık"})).status_code == 204
    assert (await client.get(f"/admin/contests/{contest['id']}", headers=boss)).json()["status"] == "cancelled"
    assert (await client.get(f"/contests/{contest['id']}", headers=cem)).status_code == 404

    # Duyuru: kitle sayısı, uygulama içi bildirim kendi dilinde, ana sayfa bandı
    assert (await client.get("/admin/announcements/audience?kind=all", headers=boss)).json()["count"] == 3
    body = {"channels": ["inbox", "banner"], "title_tr": "Yeni harita", "title_en": "New map", "body_tr": "Hemen dene",
            "body_en": "Try it now", "link": "/maptab", "audience": {"kind": "all"}}
    sent = (await client.post("/admin/announcements", headers=boss, json=body)).json()
    assert sent["recipient_count"] == 3
    note = (await notifications(client, cem))["items"][0]
    assert note["type"] == "announcement" and note["text"] == "Yeni harita: Hemen dene" and note["data"]["link"] == "/maptab"
    banner = (await client.get("/announcements/banner?locale=en")).json()
    assert banner["title"] == "New map" and banner["link"] == "/maptab"
    await client.post(f"/admin/announcements/{sent['id']}/end-banner", headers=boss)
    assert (await client.get("/announcements/banner")).json() is None

    # Yöneticiler: ekle, sahip kaldırılamaz; işlem kaydı her şeyi tutar
    assert (await client.post("/admin/admins", headers=boss, json={"username": "cem"})).status_code == 204
    team = (await client.get("/admin/admins", headers=boss)).json()
    assert {a["username"] for a in team} == {"patron", "cem"}
    assert (await client.delete(f"/admin/admins/{me_id}", headers=cem)).status_code == 403
    log = (await client.get("/admin/log", headers=boss)).json()
    actions = [i["action"] for i in log["items"]]
    for a in ("report_hide_photo", "photo_unhide", "photo_delete", "user_disable", "community_hide", "community_transfer",
              "contest_cancel", "announcement_send", "admin_add"):
        assert a in actions, a
    hide = next(i for i in log["items"] if i["action"] == "report_hide_photo")
    assert hide["note"] == "Kural ihlali" and hide["admin"]["username"] == "patron"
    assert (await client.get("/admin/log?kind=team", headers=boss)).json()["total"] == 1


async def test_admin_community_delete_and_contest_dates(client, fake_storage):
    boss, _ = await register(client, "mbektas7")
    ayse, _ = await register(client, "ayse")
    await make_admin("mbektas7")
    slug = await make_community(client, ayse)
    contest = (await client.post(f"/communities/{slug}/contests", headers=ayse, json=contest_body("jury"))).json()
    c = (await client.get(f"/admin/contests/{contest['id']}", headers=boss)).json()
    assert c["judge_count"] == 0 and c["status"] == "draft"
    bad = {"submission_deadline": c["voting_end"], "voting_end": c["submission_deadline"], "results_at": c["results_at"]}
    assert (await client.post(f"/admin/contests/{contest['id']}/dates", headers=boss, json=bad)).status_code == 422
    ok = {"submission_deadline": c["submission_deadline"], "voting_end": c["results_at"], "results_at": c["results_at"]}
    assert (await client.post(f"/admin/contests/{contest['id']}/dates", headers=boss, json=ok)).status_code == 204
    cid = (await client.get("/admin/communities?q=trabzon", headers=boss)).json()["items"][0]["id"]
    assert (await client.post(f"/admin/communities/{cid}/delete", headers=boss, json={})).status_code == 204
    assert (await client.get(f"/communities/{slug}", headers=ayse)).status_code == 404
    assert (await client.get("/admin/communities", headers=boss)).json()["total"] == 0
    # Gerçek sahip kullanıcı adıyla: kendini yöneticilikten çıkaramaz
    me = (await client.get("/me", headers=boss)).json()["id"]
    assert (await client.delete(f"/admin/admins/{me}", headers=boss)).status_code == 403


async def test_cover_cropped_below_1080_is_accepted():
    """Kapak kırpılırken yakınlaştırılınca genişlik 1080'in altına düşer; 600 px üstü kabul edilir."""
    import io

    from PIL import Image

    from app.core.config import get_settings
    from app.services.profile_images import ProfileImageError, process_profile_image

    def jpeg(w, h):
        b = io.BytesIO()
        Image.new("RGB", (w, h), (90, 90, 90)).save(b, "JPEG")
        return b.getvalue()

    out = Image.open(io.BytesIO(process_profile_image(jpeg(960, 320), "cover", get_settings())))
    assert out.size == (1800, 600)
    with pytest.raises(ProfileImageError):
        process_profile_image(jpeg(500, 167), "cover", get_settings())
