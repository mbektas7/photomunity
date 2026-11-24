"""Ekipmana göre keşif: EXIF'teki kamera modeli / lens adına göre kareler ve istatistikler.

Eşleşme normalize edilmiş tam eşitliktir: baş/son boşluk atılır, büyük/küçük harf yok sayılır.
Yalnızca herkese açık ve aktif profillerin yayındaki, gizlenmemiş kareleri sayılır; engeller iki yönlü uygulanır.
"""
import statistics
from typing import Literal

from fastapi import APIRouter, Depends, Query
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.api.deps import get_optional_user, not_blocked
from app.api.v1.photos import _cards
from app.core.database import get_db
from app.core.errors import AppError
from app.models import Photo, PhotoExif, PhotoStatus, User
from app.schemas import GearName, GearSettings, GearStats, PhotoPage, UserCard
from app.services.exif import shutter_display
from app.services.themes import like_counts_subquery

router = APIRouter(prefix="/gear", tags=["gear"])


def _norm(col):
    return func.lower(func.trim(col))


def _filters(camera: str | None, lens: str | None, viewer: User | None) -> list:
    camera, lens = (camera or "").strip(), (lens or "").strip()
    if not camera and not lens:
        raise AppError(422, "gear_required")
    conds = [Photo.status == PhotoStatus.published, Photo.hidden.is_(False), User.is_active.is_(True),
             User.is_public.is_(True), *not_blocked(Photo.user_id, viewer)]
    if camera:
        conds.append(_norm(PhotoExif.camera_model) == camera.lower())
    if lens:
        conds.append(_norm(PhotoExif.lens) == lens.lower())
    return conds


def _base(*cols):
    return (select(*cols).select_from(Photo).join(PhotoExif, PhotoExif.photo_id == Photo.id)
            .join(User, User.id == Photo.user_id))


@router.get("/photos", response_model=PhotoPage)
async def gear_photos(camera: str | None = Query(None, max_length=100), lens: str | None = Query(None, max_length=150),
                      sort: Literal["recent", "popular"] = "recent", cursor: str | None = None,
                      limit: int = Query(24, ge=1, le=60), viewer: User | None = Depends(get_optional_user),
                      db: AsyncSession = Depends(get_db)):
    try:
        off = max(0, int(cursor)) if cursor else 0
    except ValueError:
        off = 0
    q = _base(Photo).where(*_filters(camera, lens, viewer)).options(selectinload(Photo.user))
    if sort == "popular":
        likes = like_counts_subquery()
        q = q.outerjoin(likes, likes.c.photo_id == Photo.id).order_by(
            func.coalesce(likes.c.n, 0).desc(), Photo.published_at.desc(), Photo.id)
    else:
        q = q.order_by(Photo.published_at.desc(), Photo.id)
    photos = list(await db.scalars(q.offset(off).limit(limit + 1)))
    return PhotoPage(items=await _cards(db, photos[:limit], viewer), next_cursor=str(off + limit) if len(photos) > limit else None)


def _median(values: list):
    values = [v for v in values if v is not None]
    return statistics.median(values) if values else None


@router.get("/stats", response_model=GearStats)
async def gear_stats(camera: str | None = Query(None, max_length=100), lens: str | None = Query(None, max_length=150),
                     viewer: User | None = Depends(get_optional_user), db: AsyncSession = Depends(get_db)):
    """Kare ve fotoğrafçı sayısı, en çok kare paylaşan 12 fotoğrafçı ve medyan çekim ayarları (en yeni 5000 kare)."""
    conds = _filters(camera, lens, viewer)
    photo_count = await db.scalar(_base(func.count(Photo.id)).where(*conds)) or 0
    photographer_count = await db.scalar(_base(func.count(func.distinct(Photo.user_id))).where(*conds)) or 0
    top = (await db.execute(_base(Photo.user_id, func.count().label("n")).where(*conds)
                            .group_by(Photo.user_id).order_by(func.count().desc()).limit(12))).all()
    users = {u.id: u for u in await db.scalars(select(User).where(User.id.in_([r[0] for r in top])))} if top else {}
    rows = (await db.execute(_base(PhotoExif.exposure_time, PhotoExif.aperture, PhotoExif.iso, PhotoExif.focal_length_mm)
                             .where(*conds).order_by(Photo.published_at.desc()).limit(5000))).all()
    shutter = _median([r[0] for r in rows])
    iso = _median([r[2] for r in rows])
    focal = _median([r[3] for r in rows])
    aperture = _median([r[1] for r in rows])
    return GearStats(
        camera=(camera or "").strip() or None, lens=(lens or "").strip() or None, photo_count=photo_count,
        photographer_count=photographer_count,
        top_photographers=[UserCard.model_validate(users[uid]) for uid, _ in top if uid in users],
        common_settings=GearSettings(
            median_shutter_seconds=shutter, median_shutter_display=shutter_display(shutter),
            median_aperture=round(aperture, 1) if aperture is not None else None,
            median_iso=int(round(iso)) if iso is not None else None,
            median_focal_length_mm=round(focal, 1) if focal is not None else None, sample_size=len(rows)))


@router.get("/search", response_model=list[GearName])
async def gear_search(q: str = Query(min_length=1, max_length=100), kind: Literal["camera", "lens", "all"] = "all",
                      limit: int = Query(20, ge=1, le=50), db: AsyncSession = Depends(get_db)):
    """EXIF'te geçen kamera modeli / lens adları (kare sayısına göre). name, /gear/photos için birebir kullanılabilir."""
    term = q.strip().lower()
    esc = term.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
    base = [Photo.status == PhotoStatus.published, Photo.hidden.is_(False), User.is_active.is_(True), User.is_public.is_(True)]
    out: list[GearName] = []
    for k, col in (("camera", PhotoExif.camera_model), ("lens", PhotoExif.lens)):
        if kind not in (k, "all"):
            continue
        rows = (await db.execute(
            _base(func.min(func.trim(col)), func.count().label("n")).where(
                *base, col.is_not(None), _norm(col).like(f"%{esc}%", escape="\\"))
            .group_by(_norm(col)).order_by(func.count().desc()).limit(limit))).all()
        out += [GearName(kind=k, name=name, photo_count=n) for name, n in rows if name]
    return sorted(out, key=lambda g: -g.photo_count)[:limit]
