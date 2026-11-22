"""Fotoğraf yorumları: yorum, tek seviye cevap, alıntı. Sahibi yorum ayarını seçer (herkes / takipçiler / kapalı)."""
import uuid
from datetime import datetime

from fastapi import APIRouter, BackgroundTasks, Depends, Query, Response
from sqlalchemy import and_, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.api.deps import get_current_user, get_optional_user, is_following
from app.core.database import get_db
from app.core.errors import AppError
from app.core.security import utcnow
from app.models import Block, Comment, Photo, PhotoStatus, User
from app.schemas import CommentIn, CommentOut, CommentPage, CommentQuote, UserCard
from app.services.notifications import deliver, notify
from app.services.ratelimit import rate_limit

router = APIRouter(tags=["comments"])


def _live():
    return Comment.deleted_at.is_(None)


async def comment_count(db: AsyncSession, photo: Photo) -> int:
    return await db.scalar(select(func.count()).select_from(Comment).join(User, User.id == Comment.user_id).where(
        Comment.photo_id == photo.id, _live(), User.is_active.is_(True))) or 0


async def _blocked(db: AsyncSession, a: uuid.UUID, b: uuid.UUID) -> bool:
    return bool(await db.scalar(select(Block.blocker_id).where(or_(
        and_(Block.blocker_id == a, Block.blocked_id == b), and_(Block.blocker_id == b, Block.blocked_id == a)))))


async def can_comment(db: AsyncSession, photo: Photo, viewer: User | None) -> bool:
    if viewer is None or photo.status != PhotoStatus.published or photo.hidden:
        return False
    policy = photo.comment_policy or "everyone"
    if policy == "off":
        return False
    if viewer.id == photo.user_id:
        return True
    if await _blocked(db, viewer.id, photo.user_id):
        return False
    if policy == "followers":
        return await is_following(db, viewer.id, photo.user_id)
    return True


async def _photo(db: AsyncSession, photo_id: uuid.UUID, viewer: User | None) -> Photo:
    from app.api.v1.photos import _load, _visible

    return await _visible(db, await _load(db, photo_id), viewer)


async def _outs(db: AsyncSession, rows: list[Comment], photo: Photo, viewer: User | None) -> list[CommentOut]:
    if not rows:
        return []
    ids = [c.id for c in rows]
    replies = dict((await db.execute(select(Comment.parent_id, func.count()).where(
        Comment.parent_id.in_(ids), _live()).group_by(Comment.parent_id))).all())
    quote_ids = {c.quote_id for c in rows if c.quote_id}
    quotes = {q.id: q for q in await db.scalars(select(Comment).where(Comment.id.in_(quote_ids))
                                                 .options(selectinload(Comment.user)))} if quote_ids else {}
    out = []
    for c in rows:
        q = quotes.get(c.quote_id) if c.quote_id else None
        out.append(CommentOut(
            id=c.id, photo_id=c.photo_id, user=UserCard.model_validate(c.user), body=c.body, created_at=c.created_at,
            parent_id=c.parent_id, reply_count=replies.get(c.id, 0), by_photo_owner=c.user_id == photo.user_id,
            quote=CommentQuote(id=q.id, user=UserCard.model_validate(q.user), body=None if q.deleted_at else q.body) if q else None,
            can_delete=viewer is not None and (viewer.id in (c.user_id, photo.user_id) or viewer.is_admin),
        ))
    return out


def _visible_comments(viewer: User | None):
    conds = [_live(), User.is_active.is_(True)]
    if viewer is not None:
        blocked = select(Block.blocked_id).where(Block.blocker_id == viewer.id)
        blockers = select(Block.blocker_id).where(Block.blocked_id == viewer.id)
        conds += [Comment.user_id.not_in(blocked), Comment.user_id.not_in(blockers)]
    return and_(*conds)


@router.get("/photos/{photo_id}/comments", response_model=CommentPage)
async def list_comments(photo_id: uuid.UUID, before: datetime | None = None, limit: int = Query(20, le=50),
                        viewer: User | None = Depends(get_optional_user), db: AsyncSession = Depends(get_db)):
    """Üst yorumlar, en yeniden eskiye. Yorumlar kapalıysa liste boş döner (yorumlar silinmez)."""
    photo = await _photo(db, photo_id, viewer)
    if (photo.comment_policy or "everyone") == "off":
        return CommentPage(items=[], next_cursor=None, total=0)
    q = (select(Comment).join(User, User.id == Comment.user_id).options(selectinload(Comment.user))
         .where(Comment.photo_id == photo.id, Comment.parent_id.is_(None), _visible_comments(viewer)))
    if before:
        q = q.where(Comment.created_at < before)
    rows = list(await db.scalars(q.order_by(Comment.created_at.desc()).limit(limit + 1)))
    page = rows[:limit]
    return CommentPage(items=await _outs(db, page, photo, viewer),
                       next_cursor=page[-1].created_at.isoformat() if len(rows) > limit else None,
                       total=await comment_count(db, photo))


@router.get("/comments/{comment_id}/replies", response_model=list[CommentOut])
async def list_replies(comment_id: uuid.UUID, viewer: User | None = Depends(get_optional_user),
                       db: AsyncSession = Depends(get_db)):
    parent = await db.get(Comment, comment_id)
    if not parent or parent.parent_id is not None:
        raise AppError(404, "not_found")
    photo = await _photo(db, parent.photo_id, viewer)
    if (photo.comment_policy or "everyone") == "off":
        return []
    rows = list(await db.scalars(
        select(Comment).join(User, User.id == Comment.user_id).options(selectinload(Comment.user))
        .where(Comment.parent_id == parent.id, _visible_comments(viewer)).order_by(Comment.created_at.asc()).limit(200)))
    return await _outs(db, rows, photo, viewer)


@router.post("/photos/{photo_id}/comments", response_model=CommentOut, status_code=201,
             dependencies=[rate_limit("comment", 30, 600, by="user")])
async def add_comment(photo_id: uuid.UUID, body: CommentIn, background: BackgroundTasks,
                      user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    photo = await _photo(db, photo_id, user)
    if not await can_comment(db, photo, user):
        raise AppError(403, "comments_not_allowed")
    text = body.body.strip()
    if not text:
        raise AppError(422, "empty_message")

    parent = None
    if body.parent_id:
        parent = await db.get(Comment, body.parent_id)
        if not parent or parent.photo_id != photo.id or parent.deleted_at:
            raise AppError(404, "not_found")
        if parent.parent_id:  # cevaba cevap: aynı üst yoruma bağlanır
            parent = await db.get(Comment, parent.parent_id)
    replied_to = await db.get(Comment, body.parent_id) if body.parent_id else None
    if body.quote_id:
        quoted = await db.get(Comment, body.quote_id)
        if not quoted or quoted.photo_id != photo.id or quoted.deleted_at:
            raise AppError(404, "not_found")

    c = Comment(id=uuid.uuid4(), photo_id=photo.id, user_id=user.id, body=text,
                parent_id=parent.id if parent else None, quote_id=body.quote_id)
    db.add(c)
    notes = []
    n = await notify(db, user_id=photo.user_id, type="photo_comment", actor_id=user.id, photo_id=photo.id,
                     data={"comment_id": str(c.id), "preview": text[:80]})
    notes.append(n)
    if replied_to and replied_to.user_id != photo.user_id:
        notes.append(await notify(db, user_id=replied_to.user_id, type="comment_reply", actor_id=user.id, photo_id=photo.id,
                                  data={"comment_id": str(c.id), "preview": text[:80]}))
    await db.commit()
    ids = [x.id for x in notes if x]
    if ids:
        background.add_task(deliver, ids)
    c = await db.scalar(select(Comment).where(Comment.id == c.id).options(selectinload(Comment.user)))
    [out] = await _outs(db, [c], photo, user)
    return out


@router.delete("/comments/{comment_id}", status_code=204)
async def delete_comment(comment_id: uuid.UUID, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    """Yorumu yazan, fotoğrafın sahibi ya da yönetici siler. Cevaplar da görünmez olur."""
    c = await db.get(Comment, comment_id)
    if not c or c.deleted_at:
        raise AppError(404, "not_found")
    photo = await db.get(Photo, c.photo_id)
    if user.id not in (c.user_id, photo.user_id) and not user.is_admin:
        raise AppError(403, "forbidden")
    now = utcnow()
    c.deleted_at = now
    if c.parent_id is None:
        for r in await db.scalars(select(Comment).where(Comment.parent_id == c.id, _live())):
            r.deleted_at = now
    await db.commit()
    return Response(status_code=204)
