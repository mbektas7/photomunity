"""Harita: görünür alandaki fotoğrafçılar ve konumlu fotoğraflar, yakınlaştırmaya göre kümelenmiş.

Konumlar float kolonlarda ve (latitude, longitude) indeksiyle tutulur. Kullanıcı sayısı yüz binleri
geçtiğinde aynı uçlar PostGIS (geography + GiST) ile değiştirilebilir; istemci sözleşmesi değişmez.
"""
import math
from collections import defaultdict

from fastapi import APIRouter, Depends, Query
from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.api.deps import get_optional_user
from app.core.database import get_db
from app.core.errors import AppError
from app.models import Photo, PhotoStatus, User
from app.schemas import MapCluster, MapPhotographer, MapPhotoPoint, PhotoMap, PhotographerMap, UserCard
from app.services import storage

router = APIRouter(prefix="/map", tags=["map"])
MAX_POINTS = 5000
NO_CLUSTER_ZOOM = 13


def parse_bbox(bbox: str) -> tuple[float, float, float, float]:
    try:
        min_lng, min_lat, max_lng, max_lat = (float(x) for x in bbox.split(","))
    except ValueError:
        raise AppError(422, "invalid_bbox")
    if not (-90 <= min_lat <= max_lat <= 90 and -180 <= min_lng <= 180 and -180 <= max_lng <= 180):
        raise AppError(422, "invalid_bbox")
    return min_lng, min_lat, max_lng, max_lat


def in_bbox(lat_col, lng_col, bbox):
    min_lng, min_lat, max_lng, max_lat = bbox
    lat = lat_col.between(min_lat, max_lat)
    # Görünüm 180. meridyeni geçiyorsa (min_lng > max_lng) iki aralık
    lng = lng_col.between(min_lng, max_lng) if min_lng <= max_lng else or_(lng_col >= min_lng, lng_col <= max_lng)
    return lat & lng


def cluster(points: list[tuple[float, float, object]], zoom: int) -> tuple[list[list], list[object]]:
    """Mesafe tabanlı açgözlü kümeleme. Her nokta, merkezi yarıçap içinde kalan ilk kümeye katılır.

    Düz ızgara kümelemede ızgara çizgisi yan yana iki noktayı ayırabilir (ör. Trabzon ve Rize).
    Burada komşu hücrelerdeki kümeler de kontrol edildiği için bu sorun olmaz; hücreler yalnızca
    aramayı hızlandırır (5.000 noktada milisaniyeler).
    """
    if zoom >= NO_CLUSTER_ZOOM:
        return [], [p[2] for p in points]
    radius = 64 / (2 ** zoom)  # zoom 2 → 16°, zoom 8 → 0.25°, zoom 12 → 0.016°
    clusters: list[list] = []  # [toplam_enlem, toplam_boylam, üyeler]
    grid: dict[tuple[int, int], list[int]] = defaultdict(list)
    for lat, lng, item in points:
        cx, cy = math.floor(lat / radius), math.floor(lng / radius)
        target = None
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for idx in grid.get((cx + dx, cy + dy), ()):
                    c = clusters[idx]
                    n = len(c[2])
                    if abs(c[0] / n - lat) <= radius and abs(c[1] / n - lng) <= radius:
                        target = idx
                        break
                if target is not None:
                    break
            if target is not None:
                break
        if target is None:
            clusters.append([lat, lng, [(lat, lng, item)]])
            grid[(cx, cy)].append(len(clusters) - 1)
        else:
            c = clusters[target]
            c[0] += lat
            c[1] += lng
            c[2].append((lat, lng, item))
    groups = [c[2] for c in clusters if len(c[2]) > 1]
    singles = [c[2][0][2] for c in clusters if len(c[2]) == 1]
    return groups, singles


@router.get("/photographers", response_model=PhotographerMap)
async def photographers(bbox: str, zoom: int = Query(4, ge=0, le=22), specialty: str | None = None,
                        viewer: User | None = Depends(get_optional_user), db: AsyncSession = Depends(get_db)):
    """Yalnızca herkese açık ve konumunu paylaşmış profiller. Konumlar profilde ~5 km'ye yuvarlanmış durumda."""
    box = parse_bbox(bbox)
    rows = list(await db.scalars(select(User).where(
        User.is_public.is_(True), User.is_active.is_(True), User.latitude.is_not(None), User.longitude.is_not(None),
        in_bbox(User.latitude, User.longitude, box)).limit(MAX_POINTS)))
    if specialty:
        rows = [u for u in rows if specialty in (u.specialties or [])]
    groups, singles = cluster([(u.latitude, u.longitude, u) for u in rows], zoom)
    return PhotographerMap(
        clusters=[MapCluster(lat=sum(m[0] for m in g) / len(g), lng=sum(m[1] for m in g) / len(g), count=len(g)) for g in groups],
        photographers=[MapPhotographer(user=UserCard.model_validate(u), lat=u.latitude, lng=u.longitude, city=u.city,
                                       country=u.country, specialties=u.specialties or []) for u in singles],
        total=len(rows),
    )


def _thumb(p: Photo) -> str | None:
    v = (p.variants or {}).get("thumb")
    return storage.public_url(v["key"]) if v else None


@router.get("/photos", response_model=PhotoMap)
async def photos(bbox: str, zoom: int = Query(4, ge=0, le=22), db: AsyncSession = Depends(get_db)):
    """Sahibinin bilinçli olarak konum eklediği, yayındaki fotoğraflar (EXIF GPS kendiliğinden gösterilmez)."""
    box = parse_bbox(bbox)
    q = (select(Photo).join(User, User.id == Photo.user_id)
         .where(Photo.status == PhotoStatus.published, Photo.hidden.is_(False), Photo.latitude.is_not(None),
                User.is_public.is_(True), User.is_active.is_(True), in_bbox(Photo.latitude, Photo.longitude, box))
         .options(selectinload(Photo.user)).order_by(Photo.published_at.desc()).limit(MAX_POINTS))
    rows = list(await db.scalars(q))
    groups, singles = cluster([(p.latitude, p.longitude, p) for p in rows], zoom)
    return PhotoMap(
        # Sorgu en yeniden eskiye sıralı: kümenin ilk elemanı en yeni kare
        clusters=[MapCluster(lat=sum(m[0] for m in g) / len(g), lng=sum(m[1] for m in g) / len(g), count=len(g),
                             thumb_url=_thumb(g[0][2])) for g in groups],
        photos=[MapPhotoPoint(photo_id=p.id, lat=p.latitude, lng=p.longitude, title=p.title, thumb_url=_thumb(p),
                              user=UserCard.model_validate(p.user)) for p in singles],
        total=len(rows),
    )
