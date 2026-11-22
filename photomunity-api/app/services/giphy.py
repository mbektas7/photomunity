"""GIPHY araması ve GIF doğrulaması. Anahtar yalnız sunucuda; istemciler bu servis üzerinden arar."""
import httpx

from app.core.config import get_settings
from app.core.errors import AppError

BASE = "https://api.giphy.com/v1"


def enabled() -> bool:
    return bool(get_settings().giphy_api_key)


def _item(d: dict, kind: str) -> dict | None:
    imgs = d.get("images") or {}
    # Sohbet için yeterli, hafif sürüm: fixed_width (200 px genişlik); yoksa orijinal
    v = imgs.get("fixed_width") or imgs.get("original")
    if not v or not v.get("url"):
        return None
    try:
        return {"id": d["id"], "kind": kind, "url": v["url"], "width": int(v["width"]), "height": int(v["height"])}
    except (KeyError, ValueError, TypeError):
        return None


async def _get(path: str, params: dict) -> dict:
    if not enabled():
        raise AppError(503, "gifs_unavailable")
    async with httpx.AsyncClient(timeout=8) as client:
        try:
            r = await client.get(f"{BASE}{path}", params={"api_key": get_settings().giphy_api_key, **params})
        except httpx.HTTPError:
            raise AppError(503, "gifs_unavailable")
    if r.status_code == 404:
        raise AppError(404, "gif_not_found")
    if r.status_code != 200:
        raise AppError(503, "gifs_unavailable")
    return r.json()


async def search(q: str | None, kind: str, limit: int, offset: int, locale: str) -> list[dict]:
    section = "stickers" if kind == "sticker" else "gifs"
    params = {"limit": limit, "offset": offset, "rating": "pg-13"}
    if q:
        data = await _get(f"/{section}/search", {**params, "q": q, "lang": locale})
    else:
        data = await _get(f"/{section}/trending", params)
    return [x for x in (_item(d, kind) for d in data.get("data", [])) if x]


async def fetch(gif_id: str, kind: str) -> dict:
    """Mesajla gönderilen GIF'i kimliğinden doğrular; istemcinin verdiği URL'ye güvenilmez."""
    data = await _get(f"/gifs/{gif_id}", {})
    item = _item(data.get("data") or {}, kind)
    if not item:
        raise AppError(404, "gif_not_found")
    return item
