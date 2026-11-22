"""Site yönetim paneli (photomunity.com/admin). Yalnızca is_admin kullanıcılar; her değişiklik işlem kaydına yazılır."""
import uuid
from datetime import datetime, timedelta
from typing import Literal

from fastapi import APIRouter, BackgroundTasks, Depends, Query, Response
from fastapi.concurrency import run_in_threadpool
from pydantic import BaseModel, Field
from sqlalchemy import and_, delete, func, or_, select, update
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.api.deps import get_optional_user
from app.api.v1.moderation import require_admin
from app.api.v1.photos import _images
from app.core import database
from app.core.config import get_settings
from app.core.database import get_db
from app.core.errors import AppError
from app.core.security import as_aware, utcnow
from app.models import (
    AdminAction, Announcement, AuthIdentity, Comment, Community, CommunityJoinRequest, CommunityMember, CommunityPost,
    CommunityRole, Contest, ContestEntry, ContestJudge, DeviceToken, Follow, JuryScore, Like, Notification, Photo,
    Message, PhotoStatus, RefreshSession, Report, Subscription, User,
)
from app.schemas import ImageVariant, UserCard
from app.services import storage
from app.services.contests import contest_status, entry_counts, validate_dates
from app.services.push import get_fcm

router = APIRouter(prefix="/admin", tags=["admin"])
public = APIRouter(tags=["announcements"])


# ---------------------------------------------------------------- ortak
async def log_action(db: AsyncSession, admin: User, action: str, kind: str, target_type: str | None = None,
                     target_id: object = None, label: str | None = None, note: str | None = None) -> None:
    db.add(AdminAction(admin_id=admin.id, action=action, kind=kind, target_type=target_type,
                       target_id=str(target_id) if target_id is not None else None,
                       target_label=(label or "")[:300] or None, note=(note or "").strip() or None))


def _owner_username() -> str:
    return get_settings().admin_owner_username.lower()


class Paged(BaseModel):
    items: list
    total: int


class AdminUserRow(BaseModel):
    id: uuid.UUID
    username: str
    display_name: str
    email: str
    avatar_url: str | None
    is_pro: bool
    is_admin: bool
    is_active: bool
    email_verified: bool
    providers: list[str]
    country: str | None
    photo_count: int
    follower_count: int
    created_at: datetime


class AdminPhoto(BaseModel):
    id: uuid.UUID
    title: str | None
    user: UserCard
    images: dict[str, ImageVariant]
    status: str
    hidden: bool
    width: int | None
    height: int | None
    like_count: int
    created_at: datetime


class CommunityMini(BaseModel):
    id: uuid.UUID
    slug: str
    name: str
    logo_url: str | None


def _mini(c: Community) -> CommunityMini:
    return CommunityMini(id=c.id, slug=c.slug, name=c.name, logo_url=c.logo_url)


async def _user_rows(db: AsyncSession, users: list[User]) -> list[AdminUserRow]:
    ids = [u.id for u in users]
    if not ids:
        return []
    photos = dict((await db.execute(select(Photo.user_id, func.count()).where(
        Photo.user_id.in_(ids), Photo.status == PhotoStatus.published).group_by(Photo.user_id))).all())
    followers = dict((await db.execute(select(Follow.followee_id, func.count()).where(
        Follow.followee_id.in_(ids)).group_by(Follow.followee_id))).all())
    providers: dict[uuid.UUID, list[str]] = {}
    for uid, prov in (await db.execute(select(AuthIdentity.user_id, AuthIdentity.provider).where(AuthIdentity.user_id.in_(ids)))).all():
        providers.setdefault(uid, []).append(prov.value)
    return [AdminUserRow(id=u.id, username=u.username, display_name=u.display_name, email=u.email, avatar_url=u.avatar_url,
                         is_pro=u.is_pro, is_admin=u.is_admin, is_active=u.is_active, email_verified=u.email_verified,
                         providers=sorted(providers.get(u.id, [])), country=u.country, photo_count=photos.get(u.id, 0),
                         follower_count=followers.get(u.id, 0), created_at=u.created_at) for u in users]


async def _admin_photos(db: AsyncSession, photos: list[Photo]) -> list[AdminPhoto]:
    ids = [p.id for p in photos]
    likes = dict((await db.execute(select(Like.photo_id, func.count()).where(Like.photo_id.in_(ids)).group_by(Like.photo_id))).all()) if ids else {}
    return [AdminPhoto(id=p.id, title=p.title, user=UserCard.model_validate(p.user), images=_images(p), status=p.status.value,
                       hidden=p.hidden, width=p.width, height=p.height, like_count=likes.get(p.id, 0), created_at=p.created_at)
            for p in photos]


# ---------------------------------------------------------------- genel bakış
@router.get("/stats")
async def stats(days: int = Query(30, ge=7, le=90), _: User = Depends(require_admin), db: AsyncSession = Depends(get_db)):
    now = utcnow()
    week = now - timedelta(days=7)
    month_start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    count = lambda q: db.scalar(select(func.count()).select_from(q.subquery()))  # noqa: E731
    users_total = await db.scalar(select(func.count()).select_from(User)) or 0
    users_week = await db.scalar(select(func.count()).select_from(User).where(User.created_at >= week)) or 0
    published = select(Photo.id).where(Photo.status == PhotoStatus.published)
    photos_total = await count(published) or 0
    photos_week = await count(published.where(Photo.published_at >= week)) or 0
    pro = await db.scalar(select(func.count()).select_from(User).where(User.is_pro.is_(True))) or 0
    open_groups = (await db.execute(select(Report.target_type, Report.target_id, func.min(Report.created_at))
                                    .where(Report.status == "open").group_by(Report.target_type, Report.target_id))).all()
    overdue = sum(1 for g in open_groups if as_aware(g[2]) < now - timedelta(hours=24))
    communities = await db.scalar(select(func.count()).select_from(Community)) or 0
    communities_month = await db.scalar(select(func.count()).select_from(Community).where(Community.created_at >= month_start)) or 0
    live = list(await db.scalars(select(Contest).where(Contest.published_at.is_not(None), Contest.finalized_at.is_(None),
                                                       Contest.cancelled_at.is_(None), Contest.hidden.is_(False))))
    statuses = [contest_status(c) for c in live]

    start = (now - timedelta(days=days - 1)).replace(hour=0, minute=0, second=0, microsecond=0)
    day = func.date_trunc("day", Photo.published_at) if db.bind.dialect.name == "postgresql" else func.date(Photo.published_at)
    per_day = {str(d)[:10]: n for d, n in (await db.execute(select(day, func.count()).where(
        Photo.status == PhotoStatus.published, Photo.published_at >= start).group_by(day))).all()}
    series = [{"date": (start + timedelta(days=i)).date().isoformat(),
               "count": per_day.get((start + timedelta(days=i)).date().isoformat(), 0)} for i in range(days)]

    grace = await db.scalar(select(func.count()).select_from(Subscription).where(Subscription.status == "grace")) or 0
    awaiting = [c for c, s in zip(live, statuses) if s == "closed"]
    recent = list(await db.scalars(select(User).order_by(User.created_at.desc()).limit(5)))
    return {
        "users": {"total": users_total, "week": users_week},
        "photos": {"total": photos_total, "week": photos_week},
        "pro": {"total": pro},
        "reports": {"open": len(open_groups), "overdue": overdue},
        "communities": {"total": communities, "month": communities_month},
        "contests": {"running": len(live), "judging": statuses.count("judging")},
        "uploads": series,
        "pending": {"grace": grace, "awaiting_results": [{"id": str(c.id), "title": c.title, "results_at": c.results_at} for c in awaiting[:3]]},
        "recent_users": await _user_rows(db, recent),
    }


@router.get("/search")
async def search(q: str = Query(min_length=2), _: User = Depends(require_admin), db: AsyncSession = Depends(get_db)):
    like = f"%{q.strip()}%"
    users = list(await db.scalars(select(User).where(or_(User.username.ilike(like), User.display_name.ilike(like),
                                                         User.email.ilike(like))).limit(5)))
    photos = list(await db.scalars(select(Photo).options(selectinload(Photo.user)).where(Photo.title.ilike(like)).limit(5)))
    comms = list(await db.scalars(select(Community).where(or_(Community.name.ilike(like), Community.slug.ilike(like))).limit(5)))
    return {"users": await _user_rows(db, users), "photos": await _admin_photos(db, photos), "communities": [_mini(c) for c in comms]}


# ---------------------------------------------------------------- şikâyetler
class ReportGroupResolve(BaseModel):
    target_type: Literal["photo", "user", "comment", "message"]
    target_id: uuid.UUID
    action: Literal["dismiss", "hide_photo", "disable_user", "remove_content"]
    note: str | None = Field(default=None, max_length=1000)


@router.get("/report-groups")
async def report_groups(status: Literal["open", "resolved", "all"] = "open",
                        target_type: Literal["photo", "user", "comment", "message"] | None = None,
                        reason: str | None = None, _: User = Depends(require_admin), db: AsyncSession = Depends(get_db)):
    q = select(Report).order_by(Report.created_at.asc())
    if status != "all":
        q = q.where(Report.status == status)
    if target_type:
        q = q.where(Report.target_type == target_type)
    reports = list(await db.scalars(q.limit(2000)))
    groups: dict[tuple[str, uuid.UUID], list[Report]] = {}
    for r in reports:
        groups.setdefault((r.target_type, r.target_id), []).append(r)
    if reason:
        groups = {k: v for k, v in groups.items() if any(r.reason.value == reason for r in v)}
    keys = sorted(groups, key=lambda k: min(r.created_at for r in groups[k]))[:100]

    reporter_ids = {r.reporter_id for k in keys for r in groups[k]}
    reporters = {u.id: u for u in await db.scalars(select(User).where(User.id.in_(reporter_ids)))} if reporter_ids else {}
    photo_ids = [k[1] for k in keys if k[0] == "photo"]
    photos = {p.id: p for p in await db.scalars(select(Photo).options(selectinload(Photo.user)).where(Photo.id.in_(photo_ids)))} if photo_ids else {}
    # Yorum ve mesaj şikâyetleri: içerik ve yazarı
    comment_ids = [k[1] for k in keys if k[0] == "comment"]
    comments = {c.id: c for c in await db.scalars(select(Comment).where(Comment.id.in_(comment_ids)))} if comment_ids else {}
    message_ids = [k[1] for k in keys if k[0] == "message"]
    messages = {m.id: m for m in await db.scalars(select(Message).where(Message.id.in_(message_ids)))} if message_ids else {}
    authors = {**{c.id: c.user_id for c in comments.values()}, **{m.id: m.sender_id for m in messages.values()}}
    user_ids = ([k[1] for k in keys if k[0] == "user"] + [p.user_id for p in photos.values()] + list(authors.values()))
    users = {u.id: u for u in await db.scalars(select(User).where(User.id.in_(user_ids)))} if user_ids else {}
    owners = {r.id: r for r in await _user_rows(db, list(users.values()))}
    # Sahibin daha önce kapanmış şikâyetleri (fotoğrafları ya da kendisi hakkında)
    prior: dict[uuid.UUID, int] = {}
    if users:
        owned = select(Photo.id).where(Photo.user_id.in_(list(users)))
        rows = (await db.execute(select(Report.target_type, Report.target_id, Photo.user_id).outerjoin(
            Photo, and_(Report.target_type == "photo", Photo.id == Report.target_id)).where(
            Report.status == "resolved", or_(Report.target_id.in_(list(users)), Report.target_id.in_(owned))))).all()
        seen = set()
        for tt, tid, puid in rows:
            uid = puid if tt == "photo" else tid
            if (tt, tid) not in seen and uid in users:
                seen.add((tt, tid))
                prior[uid] = prior.get(uid, 0) + 1

    out = []
    for k in keys:
        rs = groups[k]
        photo = photos.get(k[1]) if k[0] == "photo" else None
        owner_id = photo.user_id if photo else authors.get(k[1], k[1])
        content = None
        if k[0] == "comment" and k[1] in comments:
            cm = comments[k[1]]
            content = {"body": cm.body, "photo_id": cm.photo_id, "created_at": cm.created_at, "removed": cm.deleted_at is not None}
        elif k[0] == "message" and k[1] in messages:
            mm = messages[k[1]]
            content = {"body": mm.body, "created_at": mm.created_at, "removed": not (mm.body or mm.image or mm.gif or mm.photo_id or mm.latitude is not None),
                       "image_url": storage.public_url(mm.image["key"]) if mm.image else None,
                       "gif_url": mm.gif["url"] if mm.gif else None}
        out.append({
            "target_type": k[0], "target_id": k[1],
            "status": "open" if any(r.status == "open" for r in rs) else "resolved",
            "resolution": next((r.resolution for r in rs if r.resolution), None),
            "first_at": min(r.created_at for r in rs),
            "reasons": sorted({r.reason.value for r in rs}),
            "reports": [{"id": r.id, "reason": r.reason.value, "note": r.note, "created_at": r.created_at,
                         "reporter": UserCard.model_validate(reporters[r.reporter_id]) if r.reporter_id in reporters else None}
                        for r in rs],
            "photo": (await _admin_photos(db, [photo]))[0] if photo else None,
            "content": content,
            "owner": owners.get(owner_id),
            "owner_prior_reports": prior.get(owner_id, 0),
        })
    return out


@router.post("/report-groups/resolve", status_code=204)
async def resolve_group(body: ReportGroupResolve, admin: User = Depends(require_admin), db: AsyncSession = Depends(get_db)):
    reports = list(await db.scalars(select(Report).where(Report.target_type == body.target_type, Report.target_id == body.target_id,
                                                         Report.status == "open")))
    if not reports:
        raise AppError(404, "not_found")
    photo = await db.get(Photo, body.target_id) if body.target_type == "photo" else None
    comment = await db.get(Comment, body.target_id) if body.target_type == "comment" else None
    message = await db.get(Message, body.target_id) if body.target_type == "message" else None
    author_id = comment.user_id if comment else message.sender_id if message else None
    label = (photo.title or str(photo.id)) if photo else (comment.body[:60] if comment else (message.body or "")[:60] or None if message else None)
    if body.action == "remove_content":
        if comment:
            comment.deleted_at = utcnow()
        elif message:
            if message.image:
                await run_in_threadpool(storage.delete_objects, [message.image["key"]])
            message.body, message.image, message.gif, message.photo_id = None, None, None, None
            message.latitude = message.longitude = message.location_name = None
    elif body.action == "hide_photo" and photo:
        photo.hidden = True
    elif body.action == "disable_user":
        target = await db.get(User, photo.user_id if photo else author_id or body.target_id)
        if target:
            if target.username == _owner_username():
                raise AppError(403, "forbidden")
            target.is_active = False
            label = label or f"@{target.username}"
    elif body.action == "dismiss" and photo:
        photo.hidden = False  # otomatik gizlenmiş fotoğraf geri açılır
    if label is None and body.target_type in ("user", "comment", "message"):
        u = await db.get(User, author_id or body.target_id)
        label = f"@{u.username}" if u else None
    for r in reports:
        r.status, r.resolution = "resolved", body.action
    await log_action(db, admin, f"report_{body.action}", "moderation", body.target_type, body.target_id, label, body.note)
    await db.commit()
    return Response(status_code=204)


# ---------------------------------------------------------------- kullanıcılar
@router.get("/users", response_model=Paged)
async def users(q: str | None = None, filter: Literal["all", "pro", "admin", "disabled", "unverified", "new"] = "all",
                offset: int = Query(0, ge=0), limit: int = Query(50, le=100),
                _: User = Depends(require_admin), db: AsyncSession = Depends(get_db)):
    query = select(User)
    if q:
        like = f"%{q.strip()}%"
        query = query.where(or_(User.username.ilike(like), User.display_name.ilike(like), User.email.ilike(like)))
    query = {
        "pro": lambda x: x.where(User.is_pro.is_(True)),
        "admin": lambda x: x.where(User.is_admin.is_(True)),
        "disabled": lambda x: x.where(User.is_active.is_(False)),
        "unverified": lambda x: x.where(User.email_verified.is_(False)),
        "new": lambda x: x.where(User.created_at >= utcnow() - timedelta(days=7)),
    }.get(filter, lambda x: x)(query)
    total = await db.scalar(select(func.count()).select_from(query.subquery())) or 0
    rows = list(await db.scalars(query.order_by(User.created_at.desc()).offset(offset).limit(limit)))
    return Paged(items=await _user_rows(db, rows), total=total)


@router.get("/users/{user_id}")
async def user_detail(user_id: uuid.UUID, _: User = Depends(require_admin), db: AsyncSession = Depends(get_db)):
    u = await db.get(User, user_id)
    if not u:
        raise AppError(404, "not_found")
    row = (await _user_rows(db, [u]))[0]
    last_login = await db.scalar(select(func.max(RefreshSession.created_at)).where(RefreshSession.user_id == u.id))
    platforms = sorted(set(await db.scalars(select(DeviceToken.platform).where(DeviceToken.user_id == u.id))))
    roles = list(await db.scalars(select(CommunityMember.role).where(CommunityMember.user_id == u.id)))
    subs = list(await db.scalars(select(Subscription).where(Subscription.user_id == u.id).order_by(Subscription.updated_at.desc())))
    owned = select(Photo.id).where(Photo.user_id == u.id)
    reports = await db.scalar(select(func.count(func.distinct(Report.target_id))).where(
        or_(and_(Report.target_type == "user", Report.target_id == u.id), and_(Report.target_type == "photo", Report.target_id.in_(owned))))) or 0
    return {**row.model_dump(), "city": u.city, "last_login": last_login, "platforms": platforms,
            "communities": len(roles), "communities_admin": sum(1 for r in roles if r != CommunityRole.member),
            "subscription": ({"store": subs[0].store, "product_id": subs[0].product_id, "status": subs[0].status,
                              "period_end": subs[0].period_end} if subs else None),
            "report_count": reports, "is_owner": u.username == _owner_username()}


class UserStatusIn(BaseModel):
    active: bool
    note: str | None = Field(default=None, max_length=1000)


@router.post("/users/{user_id}/status", status_code=204)
async def set_user_status(user_id: uuid.UUID, body: UserStatusIn, admin: User = Depends(require_admin), db: AsyncSession = Depends(get_db)):
    u = await db.get(User, user_id)
    if not u:
        raise AppError(404, "not_found")
    if not body.active and (u.id == admin.id or u.username == _owner_username()):
        raise AppError(403, "forbidden")
    u.is_active = body.active
    if not body.active:
        await db.execute(update(RefreshSession).where(RefreshSession.user_id == u.id).values(revoked=True))
    await log_action(db, admin, "user_enable" if body.active else "user_disable", "user", "user", u.id, f"@{u.username}", body.note)
    await db.commit()
    return Response(status_code=204)


@router.post("/users/{user_id}/logout", status_code=204)
async def logout_user(user_id: uuid.UUID, admin: User = Depends(require_admin), db: AsyncSession = Depends(get_db)):
    u = await db.get(User, user_id)
    if not u:
        raise AppError(404, "not_found")
    await db.execute(update(RefreshSession).where(RefreshSession.user_id == u.id).values(revoked=True))
    await log_action(db, admin, "user_logout", "user", "user", u.id, f"@{u.username}")
    await db.commit()
    return Response(status_code=204)


# ---------------------------------------------------------------- fotoğraflar
@router.get("/photos", response_model=Paged)
async def photos(tab: Literal["recent", "hidden", "rejected", "processing", "top"] = "recent", q: str | None = None,
                 offset: int = Query(0, ge=0), limit: int = Query(40, le=100),
                 _: User = Depends(require_admin), db: AsyncSession = Depends(get_db)):
    query = select(Photo).join(User, User.id == Photo.user_id)
    if q:
        like = f"%{q.strip()}%"
        query = query.where(or_(Photo.title.ilike(like), User.username.ilike(like)))
    order = Photo.created_at.desc()
    if tab == "recent":
        query = query.where(Photo.status == PhotoStatus.published)
    elif tab == "hidden":
        query = query.where(Photo.hidden.is_(True))
    elif tab == "rejected":
        query = query.where(Photo.status == PhotoStatus.rejected)
    elif tab == "processing":
        query = query.where(Photo.status.in_([PhotoStatus.pending, PhotoStatus.processing]))
    else:
        likes = select(Like.photo_id, func.count().label("n")).group_by(Like.photo_id).subquery()
        query = query.where(Photo.status == PhotoStatus.published).outerjoin(likes, likes.c.photo_id == Photo.id)
        order = func.coalesce(likes.c.n, 0).desc()
    total = await db.scalar(select(func.count()).select_from(query.with_only_columns(Photo.id).subquery())) or 0
    rows = list(await db.scalars(query.options(selectinload(Photo.user)).order_by(order, Photo.created_at.desc()).offset(offset).limit(limit)))
    return Paged(items=await _admin_photos(db, rows), total=total)


class BulkPhotosIn(BaseModel):
    ids: list[uuid.UUID] = Field(min_length=1, max_length=100)
    action: Literal["hide", "unhide", "delete"]
    note: str | None = Field(default=None, max_length=1000)


@router.post("/photos/bulk", status_code=204)
async def bulk_photos(body: BulkPhotosIn, background: BackgroundTasks, admin: User = Depends(require_admin),
                      db: AsyncSession = Depends(get_db)):
    rows = list(await db.scalars(select(Photo).where(Photo.id.in_(body.ids))))
    keys: list[str] = []
    for p in rows:
        await log_action(db, admin, f"photo_{body.action}", "content", "photo", p.id, p.title or str(p.id), body.note)
        if body.action == "delete":
            keys += [p.original_key] + [v["key"] for v in (p.variants or {}).values()]
        else:
            p.hidden = body.action == "hide"
    if body.action == "delete" and rows:
        # Veritabanı düzeyinde silinir; EXIF, beğeni, katılım gibi bağlı kayıtlar ON DELETE CASCADE ile gider
        await db.execute(delete(Photo).where(Photo.id.in_([p.id for p in rows])).execution_options(synchronize_session=False))
    await db.commit()
    if keys:
        background.add_task(run_in_threadpool, storage.delete_objects, keys)
    return Response(status_code=204)


# ---------------------------------------------------------------- topluluklar
async def _community_rows(db: AsyncSession, rows: list[Community]) -> list[dict]:
    ids = [c.id for c in rows]
    if not ids:
        return []
    members = dict((await db.execute(select(CommunityMember.community_id, func.count()).where(
        CommunityMember.community_id.in_(ids)).group_by(CommunityMember.community_id))).all())
    posts = dict((await db.execute(select(CommunityPost.community_id, func.count()).where(
        CommunityPost.community_id.in_(ids)).group_by(CommunityPost.community_id))).all())
    contests = dict((await db.execute(select(Contest.community_id, func.count()).where(
        Contest.community_id.in_(ids)).group_by(Contest.community_id))).all())
    owners = {u.id: u for u in await db.scalars(select(User).where(User.id.in_({c.owner_id for c in rows})))}
    return [{"id": c.id, "slug": c.slug, "name": c.name, "logo_url": c.logo_url, "city": c.city, "country": c.country,
             "owner": UserCard.model_validate(owners[c.owner_id]) if c.owner_id in owners else None,
             "join_approval": c.join_approval, "hidden": c.hidden, "member_count": members.get(c.id, 0),
             "post_count": posts.get(c.id, 0), "contest_count": contests.get(c.id, 0), "created_at": c.created_at} for c in rows]


@router.get("/communities", response_model=Paged)
async def communities(q: str | None = None, filter: Literal["all", "open", "approval", "hidden", "month"] = "all",
                      offset: int = Query(0, ge=0), limit: int = Query(50, le=100),
                      _: User = Depends(require_admin), db: AsyncSession = Depends(get_db)):
    query = select(Community)
    if q:
        like = f"%{q.strip()}%"
        query = query.where(or_(Community.name.ilike(like), Community.slug.ilike(like), Community.city.ilike(like)))
    query = {
        "open": lambda x: x.where(Community.join_approval.is_(False)),
        "approval": lambda x: x.where(Community.join_approval.is_(True)),
        "hidden": lambda x: x.where(Community.hidden.is_(True)),
        "month": lambda x: x.where(Community.created_at >= utcnow().replace(day=1, hour=0, minute=0, second=0, microsecond=0)),
    }.get(filter, lambda x: x)(query)
    total = await db.scalar(select(func.count()).select_from(query.subquery())) or 0
    rows = list(await db.scalars(query.order_by(Community.created_at.desc()).offset(offset).limit(limit)))
    return Paged(items=await _community_rows(db, rows), total=total)


async def _community(db: AsyncSession, cid: uuid.UUID) -> Community:
    c = await db.get(Community, cid)
    if not c:
        raise AppError(404, "not_found")
    return c


@router.get("/communities/{cid}")
async def community_detail(cid: uuid.UUID, _: User = Depends(require_admin), db: AsyncSession = Depends(get_db)):
    c = await _community(db, cid)
    row = (await _community_rows(db, [c]))[0]
    admins = await db.scalar(select(func.count()).select_from(CommunityMember).where(
        CommunityMember.community_id == c.id, CommunityMember.role != CommunityRole.member)) or 0
    pending = await db.scalar(select(func.count()).select_from(CommunityJoinRequest).where(CommunityJoinRequest.community_id == c.id)) or 0
    kinds = dict((await db.execute(select(CommunityPost.kind, func.count()).where(CommunityPost.community_id == c.id)
                                   .group_by(CommunityPost.kind))).all())
    return {**row, "admin_count": admins, "pending_requests": pending, "news_count": kinds.get("news", 0),
            "photo_post_count": kinds.get("photo", 0)}


class HiddenIn(BaseModel):
    hidden: bool
    note: str | None = Field(default=None, max_length=1000)


@router.post("/communities/{cid}/hidden", status_code=204)
async def community_hidden(cid: uuid.UUID, body: HiddenIn, admin: User = Depends(require_admin), db: AsyncSession = Depends(get_db)):
    c = await _community(db, cid)
    c.hidden = body.hidden
    await log_action(db, admin, "community_hide" if body.hidden else "community_unhide", "content", "community", c.id, c.name, body.note)
    await db.commit()
    return Response(status_code=204)


class TransferIn(BaseModel):
    username: str
    note: str | None = Field(default=None, max_length=1000)


@router.post("/communities/{cid}/transfer", status_code=204)
async def community_transfer(cid: uuid.UUID, body: TransferIn, admin: User = Depends(require_admin), db: AsyncSession = Depends(get_db)):
    c = await _community(db, cid)
    target = await db.scalar(select(User).where(User.username == body.username.strip().lstrip("@").lower(), User.is_active.is_(True)))
    if not target:
        raise AppError(404, "user_not_found")
    old = await db.get(CommunityMember, (c.id, c.owner_id))
    if old:
        old.role = CommunityRole.admin
    m = await db.get(CommunityMember, (c.id, target.id))
    if m:
        m.role = CommunityRole.owner
    else:
        db.add(CommunityMember(community_id=c.id, user_id=target.id, role=CommunityRole.owner))
    c.owner_id = target.id
    await log_action(db, admin, "community_transfer", "content", "community", c.id, f"{c.name} → @{target.username}", body.note)
    await db.commit()
    return Response(status_code=204)


class NoteIn(BaseModel):
    note: str | None = Field(default=None, max_length=1000)


@router.post("/communities/{cid}/delete", status_code=204)
async def community_delete(cid: uuid.UUID, body: NoteIn, admin: User = Depends(require_admin), db: AsyncSession = Depends(get_db)):
    c = await _community(db, cid)
    keys = [k for k in (c.logo_key, c.cover_key) if k]
    await log_action(db, admin, "community_delete", "content", "community", c.id, c.name, body.note)
    await db.execute(delete(Community).where(Community.id == c.id).execution_options(synchronize_session=False))
    await db.commit()
    if keys:
        await run_in_threadpool(storage.delete_objects, keys)
    return Response(status_code=204)


# ---------------------------------------------------------------- yarışmalar
def _admin_status(c: Contest) -> str:
    return "cancelled" if c.cancelled_at else contest_status(c)


async def _contest_rows(db: AsyncSession, rows: list[Contest]) -> list[dict]:
    ids = [c.id for c in rows]
    counts = await entry_counts(db, ids)
    entrants = dict((await db.execute(select(ContestEntry.contest_id, func.count(func.distinct(ContestEntry.user_id))).where(
        ContestEntry.contest_id.in_(ids)).group_by(ContestEntry.contest_id))).all()) if ids else {}
    comms = {c.id: c for c in await db.scalars(select(Community).where(Community.id.in_({c.community_id for c in rows})))} if rows else {}
    return [{"id": c.id, "title": c.title, "community": _mini(comms[c.community_id]), "judging_mode": c.judging_mode,
             "anonymous": c.anonymous, "status": _admin_status(c), "hidden": c.hidden, "entry_count": counts.get(c.id, 0),
             "entrant_count": entrants.get(c.id, 0), "submission_deadline": c.submission_deadline, "voting_end": c.voting_end,
             "results_at": c.results_at, "published_at": c.published_at} for c in rows]


@router.get("/contests", response_model=Paged)
async def contests(tab: Literal["running", "judging", "closed", "finished", "hidden", "all"] = "running", q: str | None = None,
                   _: User = Depends(require_admin), db: AsyncSession = Depends(get_db)):
    query = select(Contest)
    if q:
        query = query.where(Contest.title.ilike(f"%{q.strip()}%"))
    if tab == "hidden":
        query = query.where(or_(Contest.hidden.is_(True), Contest.cancelled_at.is_not(None)))
    rows = list(await db.scalars(query.order_by(Contest.submission_deadline.desc()).limit(500)))
    if tab in ("running", "judging", "closed", "finished"):
        want = {"running": {"open", "judging", "closed"}, "judging": {"judging"}, "closed": {"closed"}, "finished": {"finished"}}[tab]
        rows = [c for c in rows if c.cancelled_at is None and c.published_at is not None and contest_status(c) in want]
    return Paged(items=await _contest_rows(db, rows[:200]), total=len(rows))


async def _contest(db: AsyncSession, cid: uuid.UUID) -> Contest:
    c = await db.get(Contest, cid)
    if not c:
        raise AppError(404, "not_found")
    return c


@router.get("/contests/{cid}")
async def contest_detail(cid: uuid.UUID, _: User = Depends(require_admin), db: AsyncSession = Depends(get_db)):
    c = await _contest(db, cid)
    row = (await _contest_rows(db, [c]))[0]
    judges = list(await db.scalars(select(ContestJudge.id).where(ContestJudge.contest_id == c.id)))
    entries = row["entry_count"]
    done = 0
    if judges and entries:
        scored = dict((await db.execute(select(JuryScore.judge_id, func.count()).where(JuryScore.judge_id.in_(judges))
                                        .group_by(JuryScore.judge_id))).all())
        done = sum(1 for j in judges if scored.get(j, 0) >= entries)
    entry_photos = select(ContestEntry.photo_id).where(ContestEntry.contest_id == c.id)
    reported = await db.scalar(select(func.count(func.distinct(Report.target_id))).where(
        Report.target_type == "photo", Report.status == "open", Report.target_id.in_(entry_photos))) or 0
    return {**row, "judge_count": len(judges), "judges_done": done, "reported_entries": reported}


@router.post("/contests/{cid}/hidden", status_code=204)
async def contest_hidden(cid: uuid.UUID, body: HiddenIn, admin: User = Depends(require_admin), db: AsyncSession = Depends(get_db)):
    c = await _contest(db, cid)
    c.hidden = body.hidden
    await log_action(db, admin, "contest_hide" if body.hidden else "contest_unhide", "content", "contest", c.id, c.title, body.note)
    await db.commit()
    return Response(status_code=204)


class ExtendIn(BaseModel):
    submission_deadline: datetime
    voting_end: datetime
    results_at: datetime
    note: str | None = Field(default=None, max_length=1000)


@router.post("/contests/{cid}/dates", status_code=204)
async def contest_dates(cid: uuid.UUID, body: ExtendIn, admin: User = Depends(require_admin), db: AsyncSession = Depends(get_db)):
    c = await _contest(db, cid)
    if c.finalized_at or c.cancelled_at or not validate_dates(body.submission_deadline, body.voting_end, body.results_at, require_future=False):
        raise AppError(422, "invalid_dates")
    c.submission_deadline, c.voting_end, c.results_at = body.submission_deadline, body.voting_end, body.results_at
    await log_action(db, admin, "contest_dates", "content", "contest", c.id, c.title, body.note)
    await db.commit()
    return Response(status_code=204)


@router.post("/contests/{cid}/cancel", status_code=204)
async def contest_cancel(cid: uuid.UUID, body: NoteIn, admin: User = Depends(require_admin), db: AsyncSession = Depends(get_db)):
    c = await _contest(db, cid)
    if c.finalized_at:
        raise AppError(409, "already_finalized")
    c.cancelled_at, c.hidden = utcnow(), True
    await log_action(db, admin, "contest_cancel", "content", "contest", c.id, c.title, body.note)
    await db.commit()
    return Response(status_code=204)


# ---------------------------------------------------------------- abonelikler
@router.get("/subscriptions")
async def subscriptions(store: Literal["app_store", "play_store", "stripe"] | None = None,
                        status: Literal["active", "grace", "cancelled", "expired"] | None = None,
                        _: User = Depends(require_admin), db: AsyncSession = Depends(get_db)):
    now = utcnow()
    month_end = (now.replace(day=1) + timedelta(days=32)).replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    summary = {
        "active": await db.scalar(select(func.count()).select_from(Subscription).where(Subscription.status == "active")) or 0,
        "not_renewing": await db.scalar(select(func.count()).select_from(Subscription).where(
            Subscription.status == "active", Subscription.will_renew.is_(False))) or 0,
        "grace": await db.scalar(select(func.count()).select_from(Subscription).where(Subscription.status == "grace")) or 0,
        "ending_this_month": await db.scalar(select(func.count()).select_from(Subscription).where(
            Subscription.status.in_(["active", "grace"]), Subscription.will_renew.is_(False),
            Subscription.period_end >= now, Subscription.period_end < month_end)) or 0,
    }
    q = select(Subscription)
    if store:
        q = q.where(Subscription.store == store)
    if status:
        q = q.where(Subscription.status == status)
    rows = list(await db.scalars(q.order_by(Subscription.updated_at.desc()).limit(200)))
    users = {u.id: u for u in await db.scalars(select(User).where(User.id.in_({s.user_id for s in rows})))} if rows else {}
    return {"summary": summary, "items": [
        {"id": s.id, "user": UserCard.model_validate(users[s.user_id]) if s.user_id in users else None, "store": s.store,
         "product_id": s.product_id, "status": s.status, "will_renew": s.will_renew, "period_end": s.period_end} for s in rows]}


# ---------------------------------------------------------------- duyurular
class Audience(BaseModel):
    kind: Literal["all", "pro", "community", "locale", "country"] = "all"
    value: str | None = Field(default=None, max_length=100)


class AnnouncementIn(BaseModel):
    channels: list[Literal["push", "inbox", "banner"]] = Field(min_length=1)
    title_tr: str = Field(min_length=1, max_length=120)
    title_en: str = Field(min_length=1, max_length=120)
    body_tr: str = Field(min_length=1, max_length=400)
    body_en: str = Field(min_length=1, max_length=400)
    link: str | None = Field(default=None, max_length=300, pattern=r"^/[^\s]*$")
    audience: Audience = Audience()
    banner_days: int = Field(default=7, ge=1, le=60)
    test: bool = False


def _audience_query(a: Audience):
    q = select(User.id).where(User.is_active.is_(True))
    if a.kind == "pro":
        q = q.where(User.is_pro.is_(True))
    elif a.kind == "locale" and a.value:
        q = q.where(User.locale == a.value)
    elif a.kind == "country" and a.value:
        q = q.where(User.country == a.value.upper())
    elif a.kind == "community" and a.value:
        q = q.join(CommunityMember, CommunityMember.user_id == User.id).join(
            Community, Community.id == CommunityMember.community_id).where(Community.slug == a.value)
    return q


@router.get("/announcements/audience")
async def audience_size(kind: Literal["all", "pro", "community", "locale", "country"] = "all", value: str | None = None,
                        _: User = Depends(require_admin), db: AsyncSession = Depends(get_db)):
    q = _audience_query(Audience(kind=kind, value=value))
    return {"count": await db.scalar(select(func.count()).select_from(q.subquery())) or 0}


async def _push_announcement(user_ids: list[uuid.UUID], a: dict) -> None:
    """Arka planda: her alıcıya kendi dilinde başlık ve metinle push."""
    fcm = get_fcm()
    async with database.SessionLocal() as db:
        for i in range(0, len(user_ids), 500):
            chunk = user_ids[i:i + 500]
            locales = dict((await db.execute(select(User.id, User.locale).where(User.id.in_(chunk)))).all())
            invalid: list[str] = []
            for uid, token in (await db.execute(select(DeviceToken.user_id, DeviceToken.token).where(DeviceToken.user_id.in_(chunk)))).all():
                lang = "tr" if locales.get(uid) == "tr" else "en"
                data = {"type": "announcement", **({"link": a["link"]} if a.get("link") else {})}
                if fcm is None:
                    import logging
                    logging.getLogger("photomunity.notifications").info("push (dev) duyuru -> %s: %s", uid, a[f"title_{lang}"])
                    continue
                if not await fcm.send(token, a[f"title_{lang}"], a[f"body_{lang}"], data):
                    invalid.append(token)
            if invalid:
                await db.execute(delete(DeviceToken).where(DeviceToken.token.in_(invalid)))
        await db.commit()


@router.post("/announcements")
async def send_announcement(body: AnnouncementIn, background: BackgroundTasks, admin: User = Depends(require_admin),
                            db: AsyncSession = Depends(get_db)):
    texts = body.model_dump(include={"title_tr", "title_en", "body_tr", "body_en", "link"})
    recipients = [admin.id] if body.test else list(await db.scalars(_audience_query(body.audience)))
    if body.test:
        if "inbox" in body.channels:
            db.add(Notification(user_id=admin.id, type="announcement", data={k: v for k, v in texts.items() if v}))
        await db.commit()
        if "push" in body.channels:
            background.add_task(_push_announcement, recipients, texts)
        return {"recipient_count": 1, "test": True}

    a = Announcement(admin_id=admin.id, channels=body.channels, audience=body.audience.model_dump(), link=body.link,
                     title_tr=body.title_tr, title_en=body.title_en, body_tr=body.body_tr, body_en=body.body_en,
                     recipient_count=len(recipients),
                     banner_until=utcnow() + timedelta(days=body.banner_days) if "banner" in body.channels else None)
    db.add(a)
    if "inbox" in body.channels:
        data = {k: v for k, v in texts.items() if v}
        db.add_all([Notification(user_id=uid, type="announcement", data=data) for uid in recipients])
    await log_action(db, admin, "announcement_send", "announcement", "announcement", None, body.title_tr,
                     f"{', '.join(body.channels)} · {len(recipients)}")
    await db.commit()
    if "push" in body.channels:
        background.add_task(_push_announcement, recipients, texts)
    return {"id": a.id, "recipient_count": len(recipients), "test": False}


@router.get("/announcements")
async def announcements(_: User = Depends(require_admin), db: AsyncSession = Depends(get_db)):
    rows = list(await db.scalars(select(Announcement).order_by(Announcement.created_at.desc()).limit(50)))
    return [{"id": a.id, "channels": a.channels, "title_tr": a.title_tr, "title_en": a.title_en, "body_tr": a.body_tr,
             "body_en": a.body_en, "link": a.link, "audience": a.audience, "recipient_count": a.recipient_count,
             "banner_until": a.banner_until, "created_at": a.created_at} for a in rows]


@router.post("/announcements/{aid}/end-banner", status_code=204)
async def end_banner(aid: uuid.UUID, admin: User = Depends(require_admin), db: AsyncSession = Depends(get_db)):
    a = await db.get(Announcement, aid)
    if not a:
        raise AppError(404, "not_found")
    a.banner_until = utcnow()
    await log_action(db, admin, "announcement_end_banner", "announcement", "announcement", a.id, a.title_tr)
    await db.commit()
    return Response(status_code=204)


@public.get("/announcements/banner")
async def active_banner(locale: str = "tr", viewer: User | None = Depends(get_optional_user), db: AsyncSession = Depends(get_db)):
    """Ana sayfa bandı: süresi dolmamış en yeni duyuru; kitle kuralı oturum açmış kullanıcıya uygulanır."""
    rows = list(await db.scalars(select(Announcement).where(Announcement.banner_until > utcnow())
                                 .order_by(Announcement.created_at.desc()).limit(10)))
    for a in rows:
        aud = Audience(**(a.audience or {}))
        if aud.kind != "all":
            if viewer is None:
                continue
            ok = await db.scalar(_audience_query(aud).where(User.id == viewer.id))
            if not ok:
                continue
        lang = "tr" if (viewer.locale if viewer else locale) == "tr" else "en"
        return {"id": a.id, "title": getattr(a, f"title_{lang}"), "body": getattr(a, f"body_{lang}"), "link": a.link}
    return None


# ---------------------------------------------------------------- yöneticiler ve kayıt
@router.get("/admins")
async def admins(_: User = Depends(require_admin), db: AsyncSession = Depends(get_db)):
    rows = list(await db.scalars(select(User).where(User.is_admin.is_(True)).order_by(User.created_at)))
    since = dict((await db.execute(select(AdminAction.target_id, func.max(AdminAction.created_at)).where(
        AdminAction.action == "admin_add").group_by(AdminAction.target_id))).all())
    return [{**UserCard.model_validate(u).model_dump(), "is_owner": u.username == _owner_username(),
             "since": since.get(str(u.id))} for u in rows]


class AdminAddIn(BaseModel):
    username: str


@router.post("/admins", status_code=204)
async def add_admin(body: AdminAddIn, admin: User = Depends(require_admin), db: AsyncSession = Depends(get_db)):
    u = await db.scalar(select(User).where(User.username == body.username.strip().lstrip("@").lower(), User.is_active.is_(True)))
    if not u:
        raise AppError(404, "user_not_found")
    u.is_admin = True
    await log_action(db, admin, "admin_add", "team", "user", u.id, f"@{u.username}")
    await db.commit()
    return Response(status_code=204)


@router.delete("/admins/{user_id}", status_code=204)
async def remove_admin(user_id: uuid.UUID, admin: User = Depends(require_admin), db: AsyncSession = Depends(get_db)):
    u = await db.get(User, user_id)
    if not u:
        raise AppError(404, "not_found")
    if u.username == _owner_username():
        raise AppError(403, "forbidden")
    u.is_admin = False
    await log_action(db, admin, "admin_remove", "team", "user", u.id, f"@{u.username}")
    await db.commit()
    return Response(status_code=204)


@router.get("/log", response_model=Paged)
async def action_log(kind: Literal["moderation", "user", "content", "announcement", "team"] | None = None,
                     offset: int = Query(0, ge=0), limit: int = Query(50, le=200),
                     _: User = Depends(require_admin), db: AsyncSession = Depends(get_db)):
    q = select(AdminAction)
    if kind:
        q = q.where(AdminAction.kind == kind)
    total = await db.scalar(select(func.count()).select_from(q.subquery())) or 0
    rows = list(await db.scalars(q.options(selectinload(AdminAction.admin)).order_by(AdminAction.created_at.desc()).offset(offset).limit(limit)))
    return Paged(items=[{"id": r.id, "action": r.action, "kind": r.kind, "target_type": r.target_type, "target_id": r.target_id,
                         "target_label": r.target_label, "note": r.note, "created_at": r.created_at,
                         "admin": UserCard.model_validate(r.admin) if r.admin else None} for r in rows], total=total)
