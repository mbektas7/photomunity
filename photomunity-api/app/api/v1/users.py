import uuid
from datetime import datetime

from fastapi import APIRouter, BackgroundTasks, Depends, Query, Response
from starlette.concurrency import run_in_threadpool
from sqlalchemy import case, delete, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import can_view_photos, get_current_user, get_optional_user, is_following
from app.core.config import get_settings
from app.core.database import get_db
from app.core.errors import AppError
from app.models import Block, Equipment, Follow, Photo, PhotoStatus, User
from app.schemas import (
    ALLOWED_CONTENT_TYPES, EquipmentIn, EquipmentOut, MeDetail, MeOut, MeUpdate, ProfileImageCompleteIn,
    ProfileImageUploadIn, ProfileOut, UploadUrlOut, UserCard, UserPage,
)
from app.services import storage
from app.services.moderation import moderate
from app.services.notifications import deliver, notify
from app.services.profile_images import ProfileImageError, process_profile_image
from app.services.ratelimit import rate_limit

router = APIRouter(tags=["users"])

LOCATION_GRID = 0.05  # ~5 km; profil konumu bu ızgaraya yuvarlanır


def _fuzz(v: float | None) -> float | None:
    return None if v is None else round(round(v / LOCATION_GRID) * LOCATION_GRID, 4)


async def _equipment(db: AsyncSession, user_id: uuid.UUID) -> list[EquipmentOut]:
    rows = await db.scalars(select(Equipment).where(Equipment.user_id == user_id).order_by(Equipment.position))
    return [EquipmentOut.model_validate(e) for e in rows]


async def _get_by_username(db: AsyncSession, username: str) -> User:
    user = await db.scalar(select(User).where(User.username == username.lower(), User.is_active.is_(True)))
    if not user:
        raise AppError(404, "not_found")
    return user


@router.get("/me", response_model=MeDetail)
async def get_me(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    return MeDetail(**MeOut.model_validate(user).model_dump(), equipment=await _equipment(db, user.id))


@router.patch("/me", response_model=MeDetail)
async def update_me(body: MeUpdate, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    data = body.model_dump(exclude_unset=True)
    if "username" in data and data["username"] != user.username:
        if await db.scalar(select(User.id).where(User.username == data["username"])):
            raise AppError(409, "username_taken")
    if "latitude" in data:
        data["latitude"] = _fuzz(data["latitude"])
    if "longitude" in data:
        data["longitude"] = _fuzz(data["longitude"])
    if "country" in data and data["country"]:
        data["country"] = data["country"].upper()
    for key, value in data.items():
        setattr(user, key, value)
    await db.commit()
    await db.refresh(user)
    return MeDetail(**MeOut.model_validate(user).model_dump(), equipment=await _equipment(db, user.id))


@router.put("/me/equipment", response_model=list[EquipmentOut])
async def replace_equipment(body: list[EquipmentIn], user: User = Depends(get_current_user),
                            db: AsyncSession = Depends(get_db)):
    if len(body) > 50:
        raise AppError(422, "invalid_state")
    await db.execute(delete(Equipment).where(Equipment.user_id == user.id))
    for i, item in enumerate(body):
        db.add(Equipment(user_id=user.id, position=i, **item.model_dump()))
    await db.commit()
    return await _equipment(db, user.id)


@router.get("/users/search", response_model=list[UserCard])
async def search_users(q: str = Query(..., min_length=1, max_length=50), limit: int = Query(20, le=50),
                       viewer: User | None = Depends(get_optional_user), db: AsyncSession = Depends(get_db)):
    """Kullanıcı adı veya görünen ada göre arama; önce kullanıcı adı başlangıcı eşleşenler."""
    term = q.strip().lstrip("@").lower()
    if not term:
        return []
    esc = term.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
    like = f"%{esc}%"
    query = select(User).where(User.is_active.is_(True),
                               or_(User.username.ilike(like, escape="\\"), User.display_name.ilike(like, escape="\\")))
    if viewer:
        # İki yönlü engel: engellediğim ya da beni engelleyen kişiler listelenmez
        blocked = select(Block.blocked_id).where(Block.blocker_id == viewer.id)
        blockers = select(Block.blocker_id).where(Block.blocked_id == viewer.id)
        query = query.where(User.id.not_in(blocked), User.id.not_in(blockers))
    starts = case((User.username.ilike(f"{esc}%", escape="\\"), 0), else_=1)
    users = await db.scalars(query.order_by(starts, func.length(User.username), User.username).limit(limit))
    return [UserCard.model_validate(u) for u in users]


@router.get("/users/{username}", response_model=ProfileOut)
async def get_profile(username: str, viewer: User | None = Depends(get_optional_user),
                      db: AsyncSession = Depends(get_db)):
    user = await _get_by_username(db, username)
    followers = await db.scalar(select(func.count()).select_from(Follow).where(Follow.followee_id == user.id))
    following = await db.scalar(select(func.count()).select_from(Follow).where(Follow.follower_id == user.id))
    photos = await db.scalar(select(func.count()).select_from(Photo)
                             .where(Photo.user_id == user.id, Photo.status == PhotoStatus.published, Photo.hidden.is_(False)))
    return ProfileOut(
        **UserCard.model_validate(user).model_dump(),
        bio=user.bio, cover_url=user.cover_url, website=user.website, specialties=user.specialties or [],
        city=user.city, country=user.country, equipment=await _equipment(db, user.id),
        followers_count=followers or 0, following_count=following or 0, photos_count=photos or 0,
        is_following=bool(viewer) and await is_following(db, viewer.id, user.id),
        is_me=bool(viewer) and viewer.id == user.id,
        can_view_photos=await can_view_photos(db, viewer, user),
    )


@router.post("/users/{username}/follow", status_code=204, dependencies=[rate_limit("follow", 120, 3600, by="user")])
async def follow(username: str, background: BackgroundTasks, viewer: User = Depends(get_current_user),
                 db: AsyncSession = Depends(get_db)):
    target = await _get_by_username(db, username)
    if target.id == viewer.id:
        raise AppError(400, "cannot_follow_self")
    if not await is_following(db, viewer.id, target.id):
        db.add(Follow(follower_id=viewer.id, followee_id=target.id))
        # Takip bırakılıp tekrar edilirse aynı bildirim ikinci kez gönderilmez
        n = await notify(db, user_id=target.id, type="new_follower", actor_id=viewer.id, dedupe=True)
        await db.commit()
        if n:
            background.add_task(deliver, [n.id])
    return Response(status_code=204)


@router.delete("/users/{username}/follow", status_code=204)
async def unfollow(username: str, viewer: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    target = await _get_by_username(db, username)
    await db.execute(delete(Follow).where(Follow.follower_id == viewer.id, Follow.followee_id == target.id))
    await db.commit()
    return Response(status_code=204)


async def _follow_page(db: AsyncSession, user_id: uuid.UUID, direction: str, before: datetime | None, limit: int):
    if direction == "followers":
        join_on, where = Follow.follower_id == User.id, Follow.followee_id == user_id
    else:
        join_on, where = Follow.followee_id == User.id, Follow.follower_id == user_id
    q = select(User, Follow.created_at).join(Follow, join_on).where(where)
    if before:
        q = q.where(Follow.created_at < before)
    rows = (await db.execute(q.order_by(Follow.created_at.desc()).limit(limit + 1))).all()
    items = [UserCard.model_validate(u) for u, _ in rows[:limit]]
    cursor = rows[limit - 1][1].isoformat() if len(rows) > limit else None
    return UserPage(items=items, next_cursor=cursor)


@router.get("/users/{username}/followers", response_model=UserPage)
async def followers(username: str, before: datetime | None = None, limit: int = Query(30, le=100),
                    db: AsyncSession = Depends(get_db)):
    user = await _get_by_username(db, username)
    return await _follow_page(db, user.id, "followers", before, limit)


@router.get("/users/{username}/following", response_model=UserPage)
async def following(username: str, before: datetime | None = None, limit: int = Query(30, le=100),
                    db: AsyncSession = Depends(get_db)):
    user = await _get_by_username(db, username)
    return await _follow_page(db, user.id, "following", before, limit)


# ---------- Profil görselleri ----------
@router.post("/me/images/upload-url", response_model=UploadUrlOut, status_code=201,
             dependencies=[rate_limit("profile_image", 30, 3600, by="user")])
async def profile_image_upload_url(body: ProfileImageUploadIn, user: User = Depends(get_current_user)):
    s = get_settings()
    ext = ALLOWED_CONTENT_TYPES.get(body.content_type.lower())
    if not ext:
        raise AppError(422, "unsupported_format")
    if body.size_bytes > s.max_profile_image_bytes:
        raise AppError(422, "file_too_large")
    key = f"uploads/{user.id}/{uuid.uuid4()}{ext}"
    signed = await run_in_threadpool(storage.presigned_upload, key, body.content_type.lower(), s.max_profile_image_bytes)
    # photo_id alanı burada yükleme anahtarının kimliğidir; istemci tamamlarken key'i geri gönderir
    return UploadUrlOut(photo_id=uuid.uuid4(), upload_url=signed["url"], fields=signed["fields"], expires_in=s.upload_url_ttl_seconds)


@router.post("/me/images/complete", response_model=MeDetail)
async def profile_image_complete(body: ProfileImageCompleteIn, background: BackgroundTasks,
                                 user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    if not body.key.startswith(f"uploads/{user.id}/") or ".." in body.key:
        raise AppError(400, "invalid_key")
    try:
        data = await run_in_threadpool(storage.get_object, body.key)
    except Exception:
        raise AppError(400, "invalid_key")
    try:
        webp = await run_in_threadpool(process_profile_image, data, body.kind, get_settings())
    except ProfileImageError as e:
        background.add_task(run_in_threadpool, storage.delete_objects, [body.key])
        raise AppError(422, e.code)
    if not (await run_in_threadpool(moderate, webp)).safe:
        background.add_task(run_in_threadpool, storage.delete_objects, [body.key])
        raise AppError(422, "inappropriate_content")

    new_key = f"photos/profile/{user.id}/{body.kind}-{uuid.uuid4().hex[:12]}.webp"
    await run_in_threadpool(storage.put_object, new_key, webp, "image/webp")
    old_key = user.avatar_key if body.kind == "avatar" else user.cover_key
    if body.kind == "avatar":
        user.avatar_key, user.avatar_url = new_key, storage.public_url(new_key)
    else:
        user.cover_key, user.cover_url = new_key, storage.public_url(new_key)
    await db.commit()
    await db.refresh(user)
    background.add_task(run_in_threadpool, storage.delete_objects, [k for k in (body.key, old_key) if k])
    return MeDetail(**MeOut.model_validate(user).model_dump(), equipment=await _equipment(db, user.id))


@router.delete("/me/images/{kind}", response_model=MeDetail)
async def delete_profile_image(kind: str, background: BackgroundTasks, user: User = Depends(get_current_user),
                               db: AsyncSession = Depends(get_db)):
    if kind not in ("avatar", "cover"):
        raise AppError(404, "not_found")
    old = user.avatar_key if kind == "avatar" else user.cover_key
    if kind == "avatar":
        user.avatar_key = user.avatar_url = None
    else:
        user.cover_key = user.cover_url = None
    await db.commit()
    await db.refresh(user)
    if old:
        background.add_task(run_in_threadpool, storage.delete_objects, [old])
    return MeDetail(**MeOut.model_validate(user).model_dump(), equipment=await _equipment(db, user.id))
