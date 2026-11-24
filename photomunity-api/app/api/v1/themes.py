"""Haftalık tema (platform geneli, jürisiz, beğeniye göre) ve site yönetiminin tema yönetimi."""
import uuid
from typing import Literal

from fastapi import APIRouter, BackgroundTasks, Depends, Query, Request, Response
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import contains_eager

from app.api.deps import can_view_photos, get_current_user, get_optional_user, owner_visible
from app.api.v1.admin import log_action
from app.api.v1.moderation import require_admin
from app.api.v1.photos import _cards
from app.core.database import get_db
from app.core.errors import AppError, request_locale
from app.core.security import as_aware
from app.models import Follow, Photo, PhotoStatus, ThemeEntry, User, WeeklyTheme
from app.schemas import (
    EntryIn, ThemeAdminOut, ThemeEntryOut, ThemeEntryPage, ThemeIn, ThemeOut, ThemePage, ThemeUpdate, ThemeWinOut,
)
from app.services import themes as svc
from app.services.notifications import deliver
from app.services.ratelimit import rate_limit

router = APIRouter(tags=["themes"])
admin_router = APIRouter(prefix="/admin/themes", tags=["admin"])


def _offset(cursor: str | None) -> int:
    try:
        return max(0, int(cursor)) if cursor else 0
    except ValueError:
        return 0


def _loc(t: WeeklyTheme, field: str, locale: str):
    return getattr(t, f"{field}_{locale}") or getattr(t, f"{field}_tr")


async def _finalize(db: AsyncSession, t: WeeklyTheme, background: BackgroundTasks | None = None) -> None:
    if t.finalized_at is not None:
        return
    created = await svc.finalize_theme(db, t)
    if t.finalized_at is not None:
        await db.commit()
        if created and background is not None:
            background.add_task(deliver, [n.id for n in created])


async def _entry_outs(db: AsyncSession, rows: list[tuple[ThemeEntry, Photo]], viewer: User | None,
                      ranks: dict | None = None) -> list[ThemeEntryOut]:
    cards = {c.id: c for c in await _cards(db, [p for _, p in rows], viewer)}
    return [ThemeEntryOut(id=e.id, theme_id=e.theme_id, created_at=e.created_at, photo=cards[p.id],
                          rank=(ranks or {}).get(e.id)) for e, p in rows]


def _entries_query(theme_id: uuid.UUID, viewer: User | None):
    conds = owner_visible(viewer)
    return (select(ThemeEntry, Photo).join(Photo, Photo.id == ThemeEntry.photo_id).join(User, User.id == Photo.user_id)
            .options(contains_eager(Photo.user))
            .where(ThemeEntry.theme_id == theme_id, Photo.status == PhotoStatus.published, Photo.hidden.is_(False), *conds))


async def _one_entry(db: AsyncSession, entry_id: uuid.UUID | None, viewer: User | None, rank: int | None = None,
                     public: bool = True) -> ThemeEntryOut | None:
    if entry_id is None:
        return None
    q = (select(ThemeEntry, Photo).join(Photo, Photo.id == ThemeEntry.photo_id).join(User, User.id == Photo.user_id)
         .options(contains_eager(Photo.user)).where(ThemeEntry.id == entry_id, Photo.status == PhotoStatus.published,
                                                     User.is_active.is_(True)))
    if public:
        q = q.where(Photo.hidden.is_(False))
    row = (await db.execute(q)).first()
    if not row:
        return None
    e, p = row
    if public and not await can_view_photos(db, viewer, p.user):
        return None
    [out] = await _entry_outs(db, [(e, p)], viewer, {e.id: rank} if rank else None)
    return out


async def theme_out(db: AsyncSession, t: WeeklyTheme, viewer: User | None, locale: str) -> ThemeOut:
    my_entry = None
    if viewer:
        mine = await db.scalar(select(ThemeEntry.id).where(ThemeEntry.theme_id == t.id, ThemeEntry.user_id == viewer.id))
        my_entry = await _one_entry(db, mine, viewer, public=False)
    return ThemeOut(id=t.id, number=t.number, title=_loc(t, "title", locale), description=_loc(t, "description", locale),
                    starts_at=t.starts_at, ends_at=t.ends_at, status=svc.theme_status(t),
                    entry_count=await svc.entry_count(db, t.id), my_entry=my_entry,
                    winner=await _one_entry(db, t.winner_entry_id, viewer, rank=1), finalized_at=t.finalized_at)


async def _get_public(db: AsyncSession, theme_id: uuid.UUID) -> WeeklyTheme:
    t = await db.get(WeeklyTheme, theme_id)
    if not t or svc.theme_status(t) == "scheduled":
        raise AppError(404, "not_found")
    return t


# ---------------------------------------------------------------- herkese açık
@router.get("/themes/current", response_model=ThemeOut)
async def current_theme(request: Request, background: BackgroundTasks, viewer: User | None = Depends(get_optional_user),
                        db: AsyncSession = Depends(get_db)):
    now = svc.utcnow()
    t = await db.scalar(select(WeeklyTheme).where(WeeklyTheme.starts_at <= now, WeeklyTheme.ends_at > now)
                        .order_by(WeeklyTheme.starts_at.desc()).limit(1))
    if not t:
        raise AppError(404, "not_found")
    return await theme_out(db, t, viewer, request_locale(request))


@router.get("/themes", response_model=ThemePage)
async def list_themes(request: Request, background: BackgroundTasks, status: Literal["past", "all"] = "past",
                      cursor: str | None = None, limit: int = Query(10, ge=1, le=30),
                      viewer: User | None = Depends(get_optional_user), db: AsyncSession = Depends(get_db)):
    """past: bitmiş temalar (en yeni önce, kazanan kartıyla). all: başlamış tüm temalar (etkin olan dahil)."""
    now = svc.utcnow()
    q = select(WeeklyTheme).where(WeeklyTheme.starts_at <= now)
    if status == "past":
        q = q.where(WeeklyTheme.ends_at <= now)
    off = _offset(cursor)
    rows = list(await db.scalars(q.order_by(WeeklyTheme.ends_at.desc()).offset(off).limit(limit + 1)))
    for t in rows[:limit]:
        await _finalize(db, t, background)
    locale = request_locale(request)
    return ThemePage(items=[await theme_out(db, t, viewer, locale) for t in rows[:limit]],
                     next_cursor=str(off + limit) if len(rows) > limit else None)


@router.get("/themes/{theme_id}", response_model=ThemeOut)
async def get_theme(theme_id: uuid.UUID, request: Request, background: BackgroundTasks,
                    viewer: User | None = Depends(get_optional_user), db: AsyncSession = Depends(get_db)):
    t = await _get_public(db, theme_id)
    await _finalize(db, t, background)
    return await theme_out(db, t, viewer, request_locale(request))


@router.get("/themes/{theme_id}/entries", response_model=ThemeEntryPage)
async def theme_entries(theme_id: uuid.UUID, sort: Literal["top", "new", "following"] = "top", cursor: str | None = None,
                        limit: int = Query(24, ge=1, le=60), viewer: User | None = Depends(get_optional_user),
                        db: AsyncSession = Depends(get_db)):
    """top: beğeniye göre (eşitlikte erken katılan önce), new: en yeni, following: takip ettiklerim (giriş gerekir)."""
    t = await _get_public(db, theme_id)
    q = _entries_query(t.id, viewer)
    if sort == "top":
        likes = svc.like_counts_subquery()
        q = q.outerjoin(likes, likes.c.photo_id == Photo.id).order_by(
            func.coalesce(likes.c.n, 0).desc(), ThemeEntry.created_at.asc(), ThemeEntry.id)
    else:
        if sort == "following":
            if viewer is None:
                raise AppError(401, "not_authenticated")
            q = q.where(Photo.user_id.in_(select(Follow.followee_id).where(Follow.follower_id == viewer.id)))
        q = q.order_by(ThemeEntry.created_at.desc(), ThemeEntry.id)
    off = _offset(cursor)
    rows = [tuple(r) for r in (await db.execute(q.offset(off).limit(limit + 1))).all()]
    page = rows[:limit]
    ranks = {e.id: off + i + 1 for i, (e, _) in enumerate(page)} if sort == "top" else None
    return ThemeEntryPage(items=await _entry_outs(db, page, viewer, ranks),
                          next_cursor=str(off + limit) if len(rows) > limit else None)


@router.post("/themes/{theme_id}/entries", response_model=ThemeEntryOut, status_code=201,
             dependencies=[rate_limit("theme_entry", 30, 3600, by="user")])
async def enter_theme(theme_id: uuid.UUID, body: EntryIn, user: User = Depends(get_current_user),
                      db: AsyncSession = Depends(get_db)):
    t = await db.get(WeeklyTheme, theme_id)
    if not t:
        raise AppError(404, "not_found")
    if svc.theme_status(t) != "active":
        raise AppError(409, "theme_not_active")
    photo = await db.get(Photo, body.photo_id)
    if not photo or photo.user_id != user.id or photo.status != PhotoStatus.published or photo.hidden:
        raise AppError(422, "photo_not_eligible")
    if await db.scalar(select(ThemeEntry.id).where(ThemeEntry.theme_id == t.id, ThemeEntry.user_id == user.id)):
        raise AppError(409, "theme_already_entered")
    e = ThemeEntry(id=uuid.uuid4(), theme_id=t.id, user_id=user.id, photo_id=photo.id)
    db.add(e)
    await db.commit()
    return await _one_entry(db, e.id, user, public=False)


@router.delete("/themes/{theme_id}/entries/me", status_code=204)
async def withdraw_theme(theme_id: uuid.UUID, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    t = await db.get(WeeklyTheme, theme_id)
    if not t:
        raise AppError(404, "not_found")
    if svc.theme_status(t) != "active":
        raise AppError(409, "theme_not_active")
    e = await db.scalar(select(ThemeEntry).where(ThemeEntry.theme_id == t.id, ThemeEntry.user_id == user.id))
    if e:
        await db.delete(e)
        await db.commit()
    return Response(status_code=204)


@router.get("/users/{username}/theme-wins", response_model=list[ThemeWinOut])
async def theme_wins(username: str, request: Request, viewer: User | None = Depends(get_optional_user),
                     db: AsyncSession = Depends(get_db)):
    """Kazanılan haftalık temalar (profil rozeti), en yeni önce."""
    owner = await db.scalar(select(User).where(User.username == username.lower(), User.is_active.is_(True)))
    if not owner:
        raise AppError(404, "not_found")
    if not await can_view_photos(db, viewer, owner):
        return []
    likes = svc.like_counts_subquery()
    rows = (await db.execute(
        select(WeeklyTheme, Photo, func.coalesce(likes.c.n, 0))
        .join(ThemeEntry, ThemeEntry.id == WeeklyTheme.winner_entry_id).join(Photo, Photo.id == ThemeEntry.photo_id)
        .join(User, User.id == Photo.user_id).outerjoin(likes, likes.c.photo_id == Photo.id)
        .options(contains_eager(Photo.user))
        .where(ThemeEntry.user_id == owner.id, Photo.status == PhotoStatus.published, Photo.hidden.is_(False))
        .order_by(WeeklyTheme.finalized_at.desc()).limit(100))).all()
    cards = {c.id: c for c in await _cards(db, [p for _, p, _ in rows], viewer)}
    locale = request_locale(request)
    return [ThemeWinOut(theme_id=t.id, number=t.number, title=_loc(t, "title", locale), won_at=t.finalized_at,
                        like_count=n, photo=cards[p.id]) for t, p, n in rows]


async def theme_win_count(db: AsyncSession, user_id: uuid.UUID) -> int:
    return await db.scalar(select(func.count()).select_from(WeeklyTheme).join(
        ThemeEntry, ThemeEntry.id == WeeklyTheme.winner_entry_id).where(ThemeEntry.user_id == user_id)) or 0


# ---------------------------------------------------------------- site yönetimi
async def _admin_out(db: AsyncSession, t: WeeklyTheme) -> ThemeAdminOut:
    return ThemeAdminOut(id=t.id, number=t.number, title_tr=t.title_tr, title_en=t.title_en,
                         description_tr=t.description_tr, description_en=t.description_en, starts_at=t.starts_at,
                         ends_at=t.ends_at, status=svc.theme_status(t), entry_count=await svc.entry_count(db, t.id),
                         winner_entry_id=t.winner_entry_id, finalized_at=t.finalized_at, created_at=t.created_at)


async def _check_dates(db: AsyncSession, starts, ends, exclude: uuid.UUID | None = None) -> None:
    if ends <= starts or ends <= svc.utcnow():
        raise AppError(422, "invalid_theme_dates")
    q = select(WeeklyTheme.id).where(WeeklyTheme.starts_at < ends, WeeklyTheme.ends_at > starts)
    if exclude:
        q = q.where(WeeklyTheme.id != exclude)
    if await db.scalar(q.limit(1)):
        raise AppError(409, "theme_overlap")


@admin_router.get("", response_model=list[ThemeAdminOut])
async def admin_themes(_: User = Depends(require_admin), db: AsyncSession = Depends(get_db)):
    rows = list(await db.scalars(select(WeeklyTheme).order_by(WeeklyTheme.number.desc()).limit(200)))
    return [await _admin_out(db, t) for t in rows]


@admin_router.post("", response_model=ThemeAdminOut, status_code=201)
async def admin_create_theme(body: ThemeIn, admin: User = Depends(require_admin), db: AsyncSession = Depends(get_db)):
    starts, ends = svc.to_utc(body.starts_at), svc.to_utc(body.ends_at)
    await _check_dates(db, starts, ends)
    number = (await db.scalar(select(func.max(WeeklyTheme.number))) or 0) + 1
    t = WeeklyTheme(id=uuid.uuid4(), number=number, title_tr=body.title_tr.strip(), title_en=body.title_en.strip(),
                    description_tr=(body.description_tr or "").strip() or None,
                    description_en=(body.description_en or "").strip() or None,
                    starts_at=starts, ends_at=ends, created_by=admin.id)
    db.add(t)
    await log_action(db, admin, "theme_create", "content", "theme", t.id, f"#{number} {t.title_tr}")
    await db.commit()
    return await _admin_out(db, t)


@admin_router.patch("/{theme_id}", response_model=ThemeAdminOut)
async def admin_update_theme(theme_id: uuid.UUID, body: ThemeUpdate, admin: User = Depends(require_admin),
                             db: AsyncSession = Depends(get_db)):
    t = await db.get(WeeklyTheme, theme_id)
    if not t:
        raise AppError(404, "not_found")
    status = svc.theme_status(t)
    if status in ("ended", "finished"):
        raise AppError(409, "invalid_state")
    data = body.model_dump(exclude_unset=True)
    starts = svc.to_utc(data["starts_at"]) if data.get("starts_at") else as_aware(t.starts_at)
    ends = svc.to_utc(data["ends_at"]) if data.get("ends_at") else as_aware(t.ends_at)
    if status == "active" and starts != as_aware(t.starts_at):
        raise AppError(409, "invalid_state")  # başlamış temanın başlangıcı değişmez
    if "starts_at" in data or "ends_at" in data:
        await _check_dates(db, starts, ends, exclude=t.id)
        t.starts_at, t.ends_at = starts, ends
    for k in ("title_tr", "title_en"):
        if data.get(k):
            setattr(t, k, data[k].strip())
    for k in ("description_tr", "description_en"):
        if k in data:
            setattr(t, k, (data[k] or "").strip() or None)
    await log_action(db, admin, "theme_update", "content", "theme", t.id, f"#{t.number} {t.title_tr}")
    await db.commit()
    return await _admin_out(db, t)


@admin_router.delete("/{theme_id}", status_code=204)
async def admin_delete_theme(theme_id: uuid.UUID, admin: User = Depends(require_admin), db: AsyncSession = Depends(get_db)):
    t = await db.get(WeeklyTheme, theme_id)
    if not t:
        raise AppError(404, "not_found")
    if svc.theme_status(t) != "scheduled":
        raise AppError(409, "theme_started")
    await log_action(db, admin, "theme_delete", "content", "theme", t.id, f"#{t.number} {t.title_tr}")
    await db.delete(t)
    await db.commit()
    return Response(status_code=204)
