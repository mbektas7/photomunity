"""Tanıtım sayfası için herkese açık sayılar (5 dakika önbellekli)."""
import time

from fastapi import APIRouter, Depends
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.models import Community, Contest, Photo, PhotoStatus, User
from app.services.contests import contest_status

router = APIRouter(tags=["stats"])
_cache: dict = {"at": 0.0, "data": None}
TTL = 300


@router.get("/stats/public")
async def public_stats(db: AsyncSession = Depends(get_db)):
    if _cache["data"] is not None and time.monotonic() - _cache["at"] < TTL:
        return _cache["data"]
    photographers = await db.scalar(select(func.count()).select_from(User).where(User.is_active.is_(True))) or 0
    photos = await db.scalar(select(func.count()).select_from(Photo).where(
        Photo.status == PhotoStatus.published, Photo.hidden.is_(False))) or 0
    communities = await db.scalar(select(func.count()).select_from(Community)) or 0
    countries = await db.scalar(select(func.count(func.distinct(User.country))).where(
        User.is_active.is_(True), User.country.is_not(None))) or 0
    published = await db.scalars(select(Contest).where(Contest.published_at.is_not(None), Contest.finalized_at.is_(None), Contest.hidden.is_(False)))
    open_contests = sum(1 for c in published if contest_status(c) in ("open", "judging"))
    data = {"photographers": photographers, "photos": photos, "communities": communities,
            "countries": countries, "open_contests": open_contests}
    _cache.update(at=time.monotonic(), data=data)
    return data
