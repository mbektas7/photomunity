import re
import unicodedata
import uuid
from datetime import datetime, timedelta

from fastapi import APIRouter, BackgroundTasks, Depends, Query, Response
from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload
from starlette.concurrency import run_in_threadpool

from app.api.deps import get_current_user, get_optional_user
from app.api.v1.photos import _cards
from app.core.config import get_settings
from app.core.database import get_db
from app.core.errors import AppError
from app.core.security import as_aware, hash_token, new_opaque_token, utcnow
from app.models import (
    Community, CommunityInvite, CommunityJoinRequest, CommunityMember, CommunityPost, CommunityRole, Contest, Photo, PhotoStatus, User,
)
from app.schemas import (
    ALLOWED_CONTENT_TYPES, AdminIn, CommunityCard, CommunityImageCompleteIn, CommunityImageUploadIn, CommunityIn,
    CommunityOut, CommunityUpdate, InviteIn, JoinRequestOut, MemberOut, MemberPage, PostIn, TokenIn, UploadUrlOut, UserCard,
)
from app.services import storage
from app.services.contests import community_role, contest_status, is_admin_role
from app.services.email import send_template
from app.services.moderation import moderate
from app.services.notifications import deliver, notify
from app.services.profile_images import ProfileImageError, process_profile_image
from app.services.ratelimit import rate_limit

router = APIRouter(tags=["communities"])

_TR = str.maketrans("çğıöşüÇĞİÖŞÜ", "cgiosuCGIOSU")


def slugify(name: str) -> str:
    s = unicodedata.normalize("NFKD", name.translate(_TR)).encode("ascii", "ignore").decode().lower()
    s = re.sub(r"[^a-z0-9]+", "-", s).strip("-")[:50]
    return s if len(s) >= 3 else f"topluluk-{s}".strip("-")


async def _get(db: AsyncSession, slug: str) -> Community:
    c = await db.scalar(select(Community).where(Community.slug == slug))
    if not c:
        raise AppError(404, "not_found")
    return c


async def _require_admin(db: AsyncSession, c: Community, user: User) -> CommunityRole:
    role = await community_role(db, c.id, user.id)
    if not is_admin_role(role):
        raise AppError(403, "forbidden")
    return role


async def _member_counts(db: AsyncSession, ids: list[uuid.UUID]) -> dict[uuid.UUID, int]:
    if not ids:
        return {}
    rows = await db.execute(select(CommunityMember.community_id, func.count())
                            .where(CommunityMember.community_id.in_(ids)).group_by(CommunityMember.community_id))
    return dict(rows.all())


async def community_cards(db: AsyncSession, communities: list[Community], viewer: User | None) -> list[CommunityCard]:
    counts = await _member_counts(db, [c.id for c in communities])
    roles = {}
    if viewer and communities:
        roles = dict((await db.execute(select(CommunityMember.community_id, CommunityMember.role).where(
            CommunityMember.user_id == viewer.id, CommunityMember.community_id.in_([c.id for c in communities])))).all())
    ids = [c.id for c in communities]
    requested: set[uuid.UUID] = set()
    pending: dict[uuid.UUID, int] = {}
    if viewer and ids:
        requested = set(await db.scalars(select(CommunityJoinRequest.community_id).where(
            CommunityJoinRequest.user_id == viewer.id, CommunityJoinRequest.community_id.in_(ids))))
        managed = [cid for cid, r in roles.items() if is_admin_role(r)]
        if managed:
            pending = dict((await db.execute(select(CommunityJoinRequest.community_id, func.count()).where(
                CommunityJoinRequest.community_id.in_(managed)).group_by(CommunityJoinRequest.community_id))).all())
    return [CommunityCard(id=c.id, slug=c.slug, name=c.name, city=c.city, country=c.country, logo_url=c.logo_url,
                          member_count=counts.get(c.id, 0), my_role=roles[c.id].value if c.id in roles else None,
                          join_approval=bool(c.join_approval), my_request=c.id in requested,
                          pending_requests=pending.get(c.id, 0) if is_admin_role(roles.get(c.id)) else None)
            for c in communities]


async def community_out(db: AsyncSession, c: Community, viewer: User | None) -> CommunityOut:
    [card] = await community_cards(db, [c], viewer)
    owner = await db.get(User, c.owner_id)
    admins = await db.scalars(select(User).join(CommunityMember, CommunityMember.user_id == User.id).where(
        CommunityMember.community_id == c.id, CommunityMember.role == CommunityRole.admin))
    contests = await db.scalars(select(Contest).where(Contest.community_id == c.id, Contest.published_at.is_not(None)))
    open_count = sum(1 for x in contests if contest_status(x) in ("open", "judging"))
    return CommunityOut(**card.model_dump(), description=c.description, cover_url=c.cover_url,
                        owner=UserCard.model_validate(owner), admins=[UserCard.model_validate(a) for a in admins],
                        open_contests=open_count, created_at=c.created_at)


# ---------- Topluluk ----------
@router.post("/communities", response_model=CommunityOut, status_code=201,
             dependencies=[rate_limit("community_create", 5, 86400, by="user")])
async def create_community(body: CommunityIn, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    slug = body.slug or slugify(body.name)
    if await db.scalar(select(Community.id).where(Community.slug == slug)):
        if body.slug:
            raise AppError(409, "slug_taken")
        slug = f"{slug[:50]}-{uuid.uuid4().hex[:4]}"
    c = Community(id=uuid.uuid4(), slug=slug, name=body.name.strip(), description=body.description, city=body.city,
                  country=body.country.upper() if body.country else None, owner_id=user.id)
    db.add(c)
    await db.flush()
    db.add(CommunityMember(community_id=c.id, user_id=user.id, role=CommunityRole.owner))
    await db.commit()
    return await community_out(db, c, user)


@router.get("/communities", response_model=list[CommunityCard])
async def list_communities(q: str | None = None, mine: bool = False, limit: int = Query(30, le=100),
                           viewer: User | None = Depends(get_optional_user), db: AsyncSession = Depends(get_db)):
    query = select(Community)
    if mine:
        if not viewer:
            return []
        query = query.join(CommunityMember, CommunityMember.community_id == Community.id).where(CommunityMember.user_id == viewer.id)
    if q:
        like = f"%{q.strip()}%"
        query = query.where(or_(Community.name.ilike(like), Community.city.ilike(like)))
    members = select(CommunityMember.community_id, func.count().label("n")).group_by(CommunityMember.community_id).subquery()
    query = query.outerjoin(members, members.c.community_id == Community.id).order_by(func.coalesce(members.c.n, 0).desc(), Community.created_at.desc())
    return await community_cards(db, list(await db.scalars(query.limit(limit))), viewer)


@router.get("/communities/{slug}", response_model=CommunityOut)
async def get_community(slug: str, viewer: User | None = Depends(get_optional_user), db: AsyncSession = Depends(get_db)):
    return await community_out(db, await _get(db, slug), viewer)


@router.patch("/communities/{slug}", response_model=CommunityOut)
async def update_community(slug: str, body: CommunityUpdate, user: User = Depends(get_current_user),
                           db: AsyncSession = Depends(get_db)):
    c = await _get(db, slug)
    await _require_admin(db, c, user)
    for k, v in body.model_dump(exclude_unset=True).items():
        setattr(c, k, v.upper() if k == "country" and v else v)
    await db.commit()
    return await community_out(db, c, user)


@router.post("/communities/{slug}/images/upload-url", response_model=UploadUrlOut, status_code=201)
async def community_image_upload_url(slug: str, body: CommunityImageUploadIn, user: User = Depends(get_current_user),
                                     db: AsyncSession = Depends(get_db)):
    c = await _get(db, slug)
    await _require_admin(db, c, user)
    s = get_settings()
    ext = ALLOWED_CONTENT_TYPES.get(body.content_type.lower())
    if not ext:
        raise AppError(422, "unsupported_format")
    if body.size_bytes > s.max_profile_image_bytes:
        raise AppError(422, "file_too_large")
    key = f"uploads/{user.id}/{uuid.uuid4()}{ext}"
    signed = await run_in_threadpool(storage.presigned_upload, key, body.content_type.lower(), s.max_profile_image_bytes)
    return UploadUrlOut(photo_id=uuid.uuid4(), upload_url=signed["url"], fields=signed["fields"], expires_in=s.upload_url_ttl_seconds)


@router.post("/communities/{slug}/images/complete", response_model=CommunityOut)
async def community_image_complete(slug: str, body: CommunityImageCompleteIn, background: BackgroundTasks,
                                   user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    c = await _get(db, slug)
    await _require_admin(db, c, user)
    if not body.key.startswith(f"uploads/{user.id}/") or ".." in body.key:
        raise AppError(400, "invalid_key")
    try:
        data = await run_in_threadpool(storage.get_object, body.key)
        webp = await run_in_threadpool(process_profile_image, data, body.kind, get_settings())
    except ProfileImageError as e:
        raise AppError(422, e.code)
    except Exception:
        raise AppError(400, "invalid_key")
    if not (await run_in_threadpool(moderate, webp)).safe:
        raise AppError(422, "inappropriate_content")
    key = f"photos/communities/{c.id}/{body.kind}-{uuid.uuid4().hex[:12]}.webp"
    await run_in_threadpool(storage.put_object, key, webp, "image/webp")
    old = c.logo_key if body.kind == "logo" else c.cover_key
    if body.kind == "logo":
        c.logo_key, c.logo_url = key, storage.public_url(key)
    else:
        c.cover_key, c.cover_url = key, storage.public_url(key)
    await db.commit()
    background.add_task(run_in_threadpool, storage.delete_objects, [k for k in (body.key, old) if k])
    return await community_out(db, c, user)


# ---------- Üyelik ----------
@router.post("/communities/{slug}/join", status_code=204,
             responses={202: {"description": "Onaylı katılım: istek oluşturuldu, yönetici onayı bekleniyor"}})
async def join(slug: str, background: BackgroundTasks, user: User = Depends(get_current_user),
               db: AsyncSession = Depends(get_db)):
    c = await _get(db, slug)
    if await community_role(db, c.id, user.id) is not None:
        return Response(status_code=204)
    if not c.join_approval:
        db.add(CommunityMember(community_id=c.id, user_id=user.id, role=CommunityRole.member))
        await db.commit()
        return Response(status_code=204)
    if not await db.get(CommunityJoinRequest, (c.id, user.id)):
        db.add(CommunityJoinRequest(community_id=c.id, user_id=user.id))
        admins = await db.scalars(select(CommunityMember.user_id).where(
            CommunityMember.community_id == c.id, CommunityMember.role.in_([CommunityRole.owner, CommunityRole.admin])))
        created = []
        for admin_id in admins:
            n = await notify(db, user_id=admin_id, type="community_join_request", actor_id=user.id,
                             data={"community_slug": c.slug, "community": c.name}, dedupe=True)
            if n:
                created.append(n.id)
        await db.commit()
        if created:
            background.add_task(deliver, created)
    return Response(status_code=202)


async def _request_or_404(db: AsyncSession, c: Community, username: str) -> CommunityJoinRequest:
    target = await db.scalar(select(User).where(User.username == username.lower()))
    req = await db.get(CommunityJoinRequest, (c.id, target.id)) if target else None
    if not req:
        raise AppError(404, "not_found")
    return req


@router.get("/communities/{slug}/join-requests", response_model=list[JoinRequestOut])
async def join_requests(slug: str, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    c = await _get(db, slug)
    await _require_admin(db, c, user)
    rows = await db.scalars(select(CommunityJoinRequest).where(CommunityJoinRequest.community_id == c.id)
                            .options(selectinload(CommunityJoinRequest.user)).order_by(CommunityJoinRequest.created_at.desc()))
    return [JoinRequestOut(user=UserCard.model_validate(r.user), created_at=r.created_at) for r in rows]


@router.post("/communities/{slug}/join-requests/{username}/approve", status_code=204)
async def approve_join_request(slug: str, username: str, background: BackgroundTasks,
                               user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    c = await _get(db, slug)
    await _require_admin(db, c, user)
    req = await _request_or_404(db, c, username)
    if not await db.get(CommunityMember, (c.id, req.user_id)):
        db.add(CommunityMember(community_id=c.id, user_id=req.user_id, role=CommunityRole.member))
    await db.delete(req)
    n = await notify(db, user_id=req.user_id, type="community_join_approved", actor_id=user.id,
                     data={"community_slug": c.slug, "community": c.name})
    await db.commit()
    if n:
        background.add_task(deliver, [n.id])
    return Response(status_code=204)


@router.post("/communities/{slug}/join-requests/{username}/decline", status_code=204)
async def decline_join_request(slug: str, username: str, user: User = Depends(get_current_user),
                               db: AsyncSession = Depends(get_db)):
    c = await _get(db, slug)
    await _require_admin(db, c, user)
    await db.delete(await _request_or_404(db, c, username))
    await db.commit()
    return Response(status_code=204)


@router.delete("/communities/{slug}/join", status_code=204)
async def leave(slug: str, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    c = await _get(db, slug)
    if c.owner_id == user.id:
        raise AppError(400, "owner_cannot_leave")
    m = await db.get(CommunityMember, (c.id, user.id))
    if m:
        await db.delete(m)
    req = await db.get(CommunityJoinRequest, (c.id, user.id))  # bekleyen isteği geri çekmek de buradan
    if req:
        await db.delete(req)
    await db.commit()
    return Response(status_code=204)


@router.get("/communities/{slug}/members", response_model=MemberPage)
async def members(slug: str, role: str | None = None, before: datetime | None = None, limit: int = Query(50, le=200),
                  db: AsyncSession = Depends(get_db)):
    c = await _get(db, slug)
    q = select(CommunityMember).where(CommunityMember.community_id == c.id).options(selectinload(CommunityMember.user))
    if role:
        q = q.where(CommunityMember.role == CommunityRole(role))
    if before:
        q = q.where(CommunityMember.joined_at < before)
    rows = list(await db.scalars(q.order_by(CommunityMember.joined_at.desc()).limit(limit + 1)))
    items = [MemberOut(user=UserCard.model_validate(m.user), role=m.role.value, joined_at=m.joined_at) for m in rows[:limit]]
    return MemberPage(items=items, next_cursor=rows[limit - 1].joined_at.isoformat() if len(rows) > limit else None)


# ---------- Yöneticiler ve davetler (yalnızca sahip) ----------
async def _require_owner(db: AsyncSession, slug: str, user: User) -> Community:
    c = await _get(db, slug)
    if c.owner_id != user.id:
        raise AppError(403, "forbidden")
    return c


async def _make_admin(db: AsyncSession, c: Community, target: User, actor: User):
    m = await db.get(CommunityMember, (c.id, target.id))
    if m and m.role == CommunityRole.owner:
        return None
    if m:
        m.role = CommunityRole.admin
    else:
        db.add(CommunityMember(community_id=c.id, user_id=target.id, role=CommunityRole.admin))
    return await notify(db, user_id=target.id, type="community_admin_invite", actor_id=actor.id,
                        data={"community_slug": c.slug, "community": c.name})


@router.post("/communities/{slug}/admins", status_code=204)
async def add_admin(slug: str, body: AdminIn, background: BackgroundTasks, user: User = Depends(get_current_user),
                    db: AsyncSession = Depends(get_db)):
    c = await _require_owner(db, slug, user)
    target = await db.scalar(select(User).where(User.username == body.username.lower(), User.is_active.is_(True)))
    if not target:
        raise AppError(404, "not_found")
    n = await _make_admin(db, c, target, user)
    await db.commit()
    if n:
        background.add_task(deliver, [n.id])
    return Response(status_code=204)


@router.delete("/communities/{slug}/admins/{username}", status_code=204)
async def remove_admin(slug: str, username: str, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    c = await _require_owner(db, slug, user)
    target = await db.scalar(select(User).where(User.username == username.lower()))
    m = await db.get(CommunityMember, (c.id, target.id)) if target else None
    if m and m.role == CommunityRole.admin:
        m.role = CommunityRole.member
        await db.commit()
    return Response(status_code=204)


@router.post("/communities/{slug}/invites", dependencies=[rate_limit("community_invite", 30, 86400, by="user")])
async def invite_admin(slug: str, body: InviteIn, background: BackgroundTasks, user: User = Depends(get_current_user),
                       db: AsyncSession = Depends(get_db)):
    """E-posta kayıtlıysa kişi hemen yönetici olur; değilse kayıt olunca kabul edeceği bir davet bağlantısı gönderilir."""
    c = await _require_owner(db, slug, user)
    email = body.email.lower()
    existing = await db.scalar(select(User).where(User.email == email, User.is_active.is_(True)))
    if existing:
        n = await _make_admin(db, c, existing, user)
        await db.commit()
        if n:
            background.add_task(deliver, [n.id])
        return {"status": "added", "user": UserCard.model_validate(existing)}
    token = new_opaque_token()
    db.add(CommunityInvite(community_id=c.id, email=email, token_hash=hash_token(token), invited_by=user.id,
                           expires_at=utcnow() + timedelta(days=14)))
    await db.commit()
    link = f"{get_settings().frontend_url}/invite/community?token={token}"
    background.add_task(send_template, email, "community_invite", user.locale, link)
    return {"status": "invited"}


@router.post("/community-invites/accept", response_model=CommunityOut)
async def accept_invite(body: TokenIn, background: BackgroundTasks, user: User = Depends(get_current_user),
                        db: AsyncSession = Depends(get_db)):
    inv = await db.scalar(select(CommunityInvite).where(CommunityInvite.token_hash == hash_token(body.token)))
    if not inv or inv.accepted_at or as_aware(inv.expires_at) < utcnow():
        raise AppError(400, "invalid_link")
    if inv.email.lower() != user.email.lower():
        raise AppError(403, "invite_email_mismatch")
    c = await db.get(Community, inv.community_id)
    inviter = await db.get(User, inv.invited_by) if inv.invited_by else user
    n = await _make_admin(db, c, user, inviter or user)
    inv.accepted_at = utcnow()
    await db.commit()
    if n:
        background.add_task(deliver, [n.id])
    return await community_out(db, c, user)


# ---------- Topluluk akışı ----------
@router.get("/communities/{slug}/posts")
async def list_posts(slug: str, before: datetime | None = None, limit: int = Query(20, le=50),
                     viewer: User | None = Depends(get_optional_user), db: AsyncSession = Depends(get_db)):
    from app.api.v1.contests import contest_cards  # döngüsel içe aktarmayı önler

    c = await _get(db, slug)
    q = (select(CommunityPost).where(CommunityPost.community_id == c.id)
         .options(selectinload(CommunityPost.author), selectinload(CommunityPost.photo).selectinload(Photo.user)))
    if before:
        q = q.where(CommunityPost.created_at < before)
    posts = list(await db.scalars(q.order_by(CommunityPost.created_at.desc()).limit(limit + 1)))
    page = posts[:limit]
    photos = [p.photo for p in page if p.photo is not None and p.photo.status == PhotoStatus.published and not p.photo.hidden]
    cards = {card.id: card for card in await _cards(db, photos, viewer)}
    contest_ids = [p.contest_id for p in page if p.contest_id]
    contests = {}
    if contest_ids:
        rows = list(await db.scalars(select(Contest).where(Contest.id.in_(contest_ids))))
        contests = {cc.id: cc for cc in await contest_cards(db, rows, viewer)}
    items = []
    for p in page:
        if p.kind == "photo" and p.photo_id not in cards:
            continue  # fotoğraf silinmiş ya da gizlenmiş
        items.append({
            "id": str(p.id), "kind": p.kind, "title": p.title, "body": p.body, "created_at": p.created_at,
            "author": UserCard.model_validate(p.author),
            "photo": cards.get(p.photo_id), "contest": contests.get(p.contest_id),
        })
    return {"items": items, "next_cursor": posts[limit - 1].created_at.isoformat() if len(posts) > limit else None}


@router.post("/communities/{slug}/posts", status_code=201, dependencies=[rate_limit("post", 60, 3600, by="user")])
async def create_post(slug: str, body: PostIn, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    c = await _get(db, slug)
    role = await community_role(db, c.id, user.id)
    if role is None:
        raise AppError(403, "not_member")
    if body.kind == "news":
        if not is_admin_role(role):
            raise AppError(403, "forbidden")
        if not (body.title or "").strip():
            raise AppError(422, "invalid_state")
    else:
        photo = await db.get(Photo, body.photo_id) if body.photo_id else None
        # Galeriden yeni yüklenen kare işlenirken de paylaşılabilir; akışta yayınlanınca görünür
        if (not photo or photo.user_id != user.id or photo.hidden
                or photo.status not in (PhotoStatus.published, PhotoStatus.processing)):
            raise AppError(422, "photo_not_eligible")
    post = CommunityPost(community_id=c.id, author_id=user.id, kind=body.kind, title=body.title, body=body.body,
                         photo_id=body.photo_id if body.kind == "photo" else None)
    db.add(post)
    await db.commit()
    return {"id": str(post.id)}


@router.delete("/communities/{slug}/posts/{post_id}", status_code=204)
async def delete_post(slug: str, post_id: uuid.UUID, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    c = await _get(db, slug)
    post = await db.get(CommunityPost, post_id)
    if not post or post.community_id != c.id:
        raise AppError(404, "not_found")
    if post.author_id != user.id and not is_admin_role(await community_role(db, c.id, user.id)):
        raise AppError(403, "forbidden")
    await db.delete(post)
    await db.commit()
    return Response(status_code=204)
