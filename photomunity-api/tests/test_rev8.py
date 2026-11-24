"""Revizyon 8: jüri notu, EXIF, yöneticiye puan dağılımı, sonuçları erken açıklama, duyuru istatistikleri."""
from datetime import timedelta

import pytest

from tests.test_api import register
from tests.test_phase1_complete import notifications, upload_photo
from tests.test_phase2 import DEADLINE, VOTING_END, clock, contest_body, make_community, outbox  # noqa: F401

pytestmark = pytest.mark.asyncio


async def test_jury_note_spread_and_announce(client, fake_storage, clock, outbox):  # noqa: F811
    owner, _ = await register(client, "org8")
    slug = await make_community(client, owner)
    cid = (await client.post(f"/communities/{slug}/contests", headers=owner, json=contest_body("jury"))).json()["id"]
    j1, _ = await register(client, "juri8a")
    j2, _ = await register(client, "juri8b")
    await client.post(f"/contests/{cid}/judges", headers=owner, json={"username": "juri8a", "weight": 2})
    await client.post(f"/contests/{cid}/judges", headers=owner, json={"username": "juri8b"})
    await client.post(f"/contests/{cid}/publish", headers=owner)

    ids, heads = [], []
    for name in ("k8a", "k8b"):
        h, _ = await register(client, name)
        photo = await upload_photo(client, h, fake_storage, title=name)
        ids.append((await client.post(f"/contests/{cid}/entries", headers=h, json={"photo_id": photo})).json()["id"])
        heads.append(h)

    clock.set(DEADLINE + timedelta(hours=1))
    assert (await client.post(f"/contests/{cid}/announce", headers=owner)).json()["error"]["code"] == "invalid_state"

    r = await client.put(f"/contests/{cid}/jury/scores/{ids[0]}", headers=j1, json={"score": 8, "note": "  Finale aday  "})
    assert r.status_code == 204
    await client.put(f"/contests/{cid}/jury/scores/{ids[1]}", headers=j1, json={"score": 6})
    await client.put(f"/contests/{cid}/jury/scores/{ids[0]}", headers=j2, json={"score": 9})
    # Notsuz puan güncellemesi notu silmez; açıkça boş gönderilirse siler
    await client.put(f"/contests/{cid}/jury/scores/{ids[0]}", headers=j1, json={"score": 9})
    view = {e["id"]: e for e in (await client.get(f"/contests/{cid}/entries", headers=j1)).json()}
    assert view[ids[0]]["my_score"] == 9 and view[ids[0]]["my_note"] == "Finale aday"
    assert view[ids[1]]["my_note"] is None and "exif" in view[ids[0]]
    assert view[ids[0]]["number"] == 1 and view[ids[1]]["number"] == 2  # karıştırılmış listede de aynı numara
    other = {e["id"]: e for e in (await client.get(f"/contests/{cid}/entries", headers=j2)).json()}
    assert other[ids[0]]["my_note"] is None  # not yalnızca yazan jüriye görünür

    preview = (await client.get(f"/contests/{cid}/results", headers=owner)).json()
    assert preview[0]["entry"]["id"] == ids[0] and preview[0]["scores"] == [9, 9]

    # Oylama bitti → organizatör ilan tarihini beklemeden açıklar
    clock.set(VOTING_END + timedelta(hours=1))
    out = (await client.post(f"/contests/{cid}/announce", headers=heads[0])).json()
    assert out["error"]["code"] == "forbidden"
    out = (await client.post(f"/contests/{cid}/announce", headers=owner)).json()
    assert out["status"] == "finished" and out["judge_count"] == 2 and out["entry_count"] == 2
    public = (await client.get(f"/contests/{cid}/results")).json()
    assert public[0]["rank"] == 1 and public[0]["prize"] == "Fujifilm X-T5" and public[0]["scores"] is None
    assert (await notifications(client, heads[0]))["items"][0]["type"] == "contest_won"
    assert (await client.post(f"/contests/{cid}/announce", headers=owner)).json()["error"]["code"] == "invalid_state"
