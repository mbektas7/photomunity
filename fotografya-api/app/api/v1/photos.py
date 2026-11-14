import uuid
from datetime import datetime

from fastapi import APIRouter, BackgroundTasks, Depends, Query, Request, Response
from sqlalchemy import delete, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload
from starlette.concurrency import run_in_threadpool

from app.api.deps import can_view_photos, get_current_user, get_optional_user
from app.core.config import get_settings
from app.core.database import get_db
from app.core.errors import AppError, request_locale
from app.core.messages import translate
from app.models import Follow, Like, Photo, PhotoStatus, User
from app.schemas import (
    ALLOWED_CONTENT_TYPES, ExifOut, ImageVariant, LocationIn, PhotoCard, PhotoDetail, PhotoMetaIn, PhotoPage,
    PhotoUpdate, UploadUrlIn, UploadUrlOut, UserCard,
)
from app.services import storage
from app.services.notifications import deliver, notify
from app.services.photo_pipeline import process_photo
from app.services.ratelimit import rate_limit

router = APIRouter(tags=["photos"])


def _images(photo: Photo) -> dict[str, ImageVariant]:
    return {name: ImageVariant(url=storage.public_url(v["key"]), width=v["width"], height=v["height"])
            for name, v in (photo.variants or {}).items()}


async def _like_stats(db: AsyncSession, photo_ids: list[uuid.UUID], viewer: User | None):
    if not photo_ids:
        return {}, set()
    counts = dict((await db.execute(
        select(Like.photo_id, func.count()).where(Like.photo_id.in_(photo_ids)).group_by(Like.photo_id))).all())
    liked = set()
    if viewer:
        liked = set(await db.scalars(select(Like.photo_id).where(Like.user_id == viewer.id,
                                                                 Like.photo_id.in_(photo_ids))))
    return counts, liked


async def _cards(db: AsyncSession, photos: list[Photo], viewer: User | None) -> list[PhotoCard]:
    counts, liked = await _like_stats(db, [p.id for p in photos], viewer)
    return [PhotoCard(id=p.id, user=UserCard.model_validate(p.user), title=p.title, images=_images(p),
                      like_count=counts.get(p.id, 0), liked_by_me=p.id in liked, published_at=p.published_at)
            for p in photos]


def _page(cards: list[PhotoCard], limit: int) -> PhotoPage:
    cursor = cards[limit - 1].published_at.isoformat() if len(cards) > limit and cards[limit - 1].published_at else None
    return PhotoPage(items=cards[:limit], next_cursor=cursor)


async def _load(db: AsyncSession, photo_id: uuid.UUID) -> Photo:
    photo = await db.scalar(select(Photo).where(Photo.id == photo_id)
                            .options(selectinload(Photo.user), selectinload(Photo.exif)))
    if not photo:
        raise AppError(404, "not_found")
    return photo


async def _visible(db: AsyncSession, photo: Photo, viewer: User | None) -> Photo:
    is_owner = viewer is not None and viewer.id == photo.user_id
    if not is_owner:
        if photo.status != PhotoStatus.published or photo.hidden or not photo.user.is_active:
            raise AppError(404, "not_found")
        if not await can_view_photos(db, viewer, photo.user):
            raise AppError(403, "private_profile")
    return photo


# ---------- Yükleme ----------
@router.post("/photos/upload-url", response_model=UploadUrlOut, status_code=201,
             dependencies=[rate_limit("upload", 60, 3600, by="user", pro_limit=200)])
async def create_upload_url(body: UploadUrlIn, user: User = Depends(get_current_user),
                            db: AsyncSession = Depends(get_db)):
    s = get_settings()
    ext = ALLOWED_CONTENT_TYPES.get(body.content_type.lower())
    codes = []
    if not ext:
        codes.append("unsupported_format")
    if body.size_bytes < s.min_file_bytes:
        codes.append("file_too_small")
    if body.size_bytes > s.max_file_bytes:
        codes.append("file_too_large")
    if codes:
        raise AppError(422, codes[0], details=codes)

    photo_id = uuid.uuid4()
    key = f"originals/{user.id}/{photo_id}/original{ext}"
    db.add(Photo(id=photo_id, user_id=user.id, original_key=key, content_type=body.content_type.lower(),
                 status=PhotoStatus.pending, tags=[], variants={}, rejection_codes=[], quality={}))
    await db.commit()
    signed = await run_in_threadpool(storage.presigned_upload, key, body.content_type.lower(), s.max_file_bytes)
    return UploadUrlOut(photo_id=photo_id, upload_url=signed["url"], fields=signed["fields"],
                        expires_in=s.upload_url_ttl_seconds)


@router.post("/photos/{photo_id}/complete", response_model=PhotoDetail, status_code=202)
async def complete_upload(photo_id: uuid.UUID, body: PhotoMetaIn, request: Request, background: BackgroundTasks,
                          user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    """İstemci dosyayı depolamaya yükledikten sonra çağırır; işleme kuyruğa alınır."""
    photo = await _load(db, photo_id)
    if photo.user_id != user.id:
        raise AppError(404, "not_found")
    if photo.status != PhotoStatus.pending:
        raise AppError(409, "invalid_state")
    _apply_meta(photo, body.title, body.description, body.tags, body.location)
    photo.status = PhotoStatus.processing
    await db.commit()

    arq = getattr(request.app.state, "arq", None)
    if arq:
        await arq.enqueue_job("process_photo_job", str(photo.id))
    else:  # Redis yoksa (geliştirme/test) aynı süreçte işle
        background.add_task(process_photo, photo.id)
    return await _detail(db, photo, user, request_locale(request))


def _apply_meta(photo: Photo, title, description, tags, location: LocationIn | None):
    if title is not None:
        photo.title = title.strip() or None
    if description is not None:
        photo.description = description.strip() or None
    if tags is not None:
        photo.tags = sorted({t.strip().lower().lstrip("#")[:40] for t in tags if t.strip()})
    if location is not None:
        photo.latitude, photo.longitude, photo.location_name = location.latitude, location.longitude, location.name


async def _detail(db: AsyncSession, photo: Photo, viewer: User | None, locale: str) -> PhotoDetail:
    [card] = await _cards(db, [photo], viewer)
    is_owner = viewer is not None and viewer.id == photo.user_id
    exif = photo.exif
    location = (LocationIn(latitude=photo.latitude, longitude=photo.longitude, name=photo.location_name)
                if photo.latitude is not None and photo.longitude is not None else None)
    suggested = None
    if is_owner and exif and exif.gps_latitude is not None and exif.gps_longitude is not None and not location:
        suggested = LocationIn(latitude=exif.gps_latitude, longitude=exif.gps_longitude)
    rejection = None
    if is_owner and photo.status == PhotoStatus.rejected:
        rejection = [{"code": c, "message": translate(c, locale)} for c in photo.rejection_codes]
    return PhotoDetail(
        **card.model_dump(), description=photo.description, tags=photo.tags or [],
        width=photo.width, height=photo.height, exif=ExifOut.model_validate(exif) if exif else None,
        location=location, status=photo.status, rejection=rejection, suggested_location=suggested,
    )


# ---------- Okuma / düzenleme ----------
@router.get("/photos/{photo_id}", response_model=PhotoDetail)
async def get_photo(photo_id: uuid.UUID, request: Request, viewer: User | None = Depends(get_optional_user),
                    db: AsyncSession = Depends(get_db)):
    photo = await _visible(db, await _load(db, photo_id), viewer)
    return await _detail(db, photo, viewer, request_locale(request))


@router.patch("/photos/{photo_id}", response_model=PhotoDetail)
async def update_photo(photo_id: uuid.UUID, body: PhotoUpdate, request: Request,
                       user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    photo = await _load(db, photo_id)
    if photo.user_id != user.id:
        raise AppError(404, "not_found")
    _apply_meta(photo, body.title, body.description, body.tags, body.location)
    if body.clear_location:
        photo.latitude = photo.longitude = photo.location_name = None
    await db.commit()
    return await _detail(db, await _load(db, photo_id), user, request_locale(request))


@router.delete("/photos/{photo_id}", status_code=204)
async def delete_photo(photo_id: uuid.UUID, background: BackgroundTasks, user: User = Depends(get_current_user),
                       db: AsyncSession = Depends(get_db)):
    photo = await _load(db, photo_id)
    if photo.user_id != user.id:
        raise AppError(404, "not_found")
    keys = [photo.original_key] + [v["key"] for v in (photo.variants or {}).values()]
    await db.delete(photo)
    await db.commit()
    background.add_task(run_in_threadpool, storage.delete_objects, keys)
    return Response(status_code=204)


# ---------- Beğeni ----------
@router.post("/photos/{photo_id}/like", status_code=204, dependencies=[rate_limit("like", 600, 3600, by="user")])
async def like(photo_id: uuid.UUID, background: BackgroundTasks, user: User = Depends(get_current_user),
               db: AsyncSession = Depends(get_db)):
    photo = await _visible(db, await _load(db, photo_id), user)
    exists = await db.scalar(select(Like.photo_id).where(Like.user_id == user.id, Like.photo_id == photo.id))
    if not exists:
        db.add(Like(user_id=user.id, photo_id=photo.id))
        n = await notify(db, user_id=photo.user_id, type="photo_liked", actor_id=user.id, photo_id=photo.id, dedupe=True)
        await db.commit()
        if n:
            background.add_task(deliver, [n.id])
    return Response(status_code=204)


@router.delete("/photos/{photo_id}/like", status_code=204)
async def unlike(photo_id: uuid.UUID, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    await db.execute(delete(Like).where(Like.user_id == user.id, Like.photo_id == photo_id))
    await db.commit()
    return Response(status_code=204)


# ---------- Akışlar ----------
def _published():
    return (select(Photo).where(Photo.status == PhotoStatus.published, Photo.hidden.is_(False))
            .options(selectinload(Photo.user)))


def _paged(q, before: datetime | None, limit: int):
    if before:
        q = q.where(Photo.published_at < before)
    return q.order_by(Photo.published_at.desc(), Photo.id.desc()).limit(limit + 1)


@router.get("/feed", response_model=PhotoPage)
async def feed(before: datetime | None = None, limit: int = Query(20, le=50),
               user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    """Kendi paylaşımları + takip edilenlerin paylaşımları (kapalı profiller de takipçiye görünür)."""
    followees = select(Follow.followee_id).where(Follow.follower_id == user.id)
    q = _published().where(or_(Photo.user_id == user.id, Photo.user_id.in_(followees)))
    photos = list(await db.scalars(_paged(q, before, limit)))
    return _page(await _cards(db, photos, user), limit)


@router.get("/explore", response_model=PhotoPage)
async def explore(before: datetime | None = None, limit: int = Query(20, le=50),
                  viewer: User | None = Depends(get_optional_user), db: AsyncSession = Depends(get_db)):
    """Herkese açık profillerin en yeni paylaşımları. Faz 2'de etkileşim bazlı sıralama gelecek."""
    q = _published().join(User, User.id == Photo.user_id).where(User.is_public.is_(True), User.is_active.is_(True))
    photos = list(await db.scalars(_paged(q, before, limit)))
    return _page(await _cards(db, photos, viewer), limit)


@router.get("/users/{username}/photos", response_model=PhotoPage)
async def user_photos(username: str, before: datetime | None = None, limit: int = Query(24, le=60),
                      viewer: User | None = Depends(get_optional_user), db: AsyncSession = Depends(get_db)):
    owner = await db.scalar(select(User).where(User.username == username.lower(), User.is_active.is_(True)))
    if not owner:
        raise AppError(404, "not_found")
    if not await can_view_photos(db, viewer, owner):
        raise AppError(403, "private_profile")
    photos = list(await db.scalars(_paged(_published().where(Photo.user_id == owner.id), before, limit)))
    return _page(await _cards(db, photos, viewer), limit)
