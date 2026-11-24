"""Eleştiri modu: sahibi eleştiri isteyen karelere puanlı (1–5) ve yazılı, yapılandırılmış geri bildirim."""
import uuid

from fastapi import APIRouter, BackgroundTasks, Depends, Query, Response
from sqlalchemy import and_, delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.api.deps import get_current_user, get_optional_user, is_following, not_blocked, owner_visible
from app.api.v1.comments import _blocked
from app.api.v1.photos import _cards, _load, _visible
from app.core.database import get_db
from app.core.errors import AppError
from app.models import Critique, CritiqueHelpful, Photo, PhotoStatus, User
from app.schemas import CritiqueAverages, CritiqueIn, CritiqueList, CritiqueOut, PhotoPage, UserCard
from app.services.notifications import deliver, notify
from app.services.ratelimit import rate_limit

router = APIRouter(tags=["critiques"])
CRITERIA = ("composition", "light", "focus", "editing")


async def _photo(db: AsyncSession, photo_id: uuid.UUID, viewer: User | None) -> Photo:
    return await _visible(db, await _load(db, photo_id), viewer)


async def _can_critique(db: AsyncSession, photo: Photo, viewer: User | None) -> str | None:
    """Engel nedeni (hata kodu) ya da None. Yorum ayarı "off" eleştiriyi kapatmaz: eleştiriyi sahibi açıkça ister."""
    if viewer is None:
        return "not_authenticated"
    if viewer.id == photo.user_id:
        return "cannot_critique_own"
    if not photo.critique_requested or photo.status != PhotoStatus.published or photo.hidden:
        return "critique_not_requested"
    if await _blocked(db, viewer.id, photo.user_id):
        return "forbidden"
    if (photo.comment_policy or "everyone") == "followers" and not await is_following(db, viewer.id, photo.user_id):
        return "comments_not_allowed"
    return None


async def _outs(db: AsyncSession, rows: list[Critique], photo: Photo, viewer: User | None) -> list[CritiqueOut]:
    if not rows:
        return []
    ids = [c.id for c in rows]
    helpful = dict((await db.execute(select(CritiqueHelpful.critique_id, func.count()).where(
        CritiqueHelpful.critique_id.in_(ids)).group_by(CritiqueHelpful.critique_id))).all())
    mine = set()
    if viewer:
        mine = set(await db.scalars(select(CritiqueHelpful.critique_id).where(
            CritiqueHelpful.user_id == viewer.id, CritiqueHelpful.critique_id.in_(ids))))
    return [CritiqueOut(
        id=c.id, photo_id=c.photo_id, user=UserCard.model_validate(c.user), author_specialties=c.user.specialties or [],
        composition=c.composition, light=c.light, focus=c.focus, editing=c.editing,
        average=round((c.composition + c.light + c.focus + c.editing) / 4, 2), good=c.good, improve=c.improve,
        helpful_count=helpful.get(c.id, 0), helpful_by_me=c.id in mine, mine=viewer is not None and viewer.id == c.user_id,
        can_delete=viewer is not None and (viewer.id in (c.user_id, photo.user_id) or viewer.is_admin),
        created_at=c.created_at, updated_at=c.updated_at) for c in rows]


def _live(photo_id: uuid.UUID, viewer: User | None):
    return and_(Critique.photo_id == photo_id, User.is_active.is_(True), *not_blocked(Critique.user_id, viewer))


@router.get("/photos/{photo_id}/critiques", response_model=CritiqueList)
async def list_critiques(photo_id: uuid.UUID, viewer: User | None = Depends(get_optional_user),
                         db: AsyncSession = Depends(get_db)):
    """Faydalı sayısına, sonra yeniliğe göre sıralı (en fazla 200). Ortalamalar tüm eleştirilerden hesaplanır."""
    photo = await _photo(db, photo_id, viewer)
    base = select(Critique).join(User, User.id == Critique.user_id).where(_live(photo.id, viewer))
    helpful = (select(CritiqueHelpful.critique_id, func.count().label("n"))
               .group_by(CritiqueHelpful.critique_id).subquery())
    rows = list(await db.scalars(
        base.options(selectinload(Critique.user)).outerjoin(helpful, helpful.c.critique_id == Critique.id)
        .order_by(func.coalesce(helpful.c.n, 0).desc(), Critique.created_at.desc()).limit(200)))
    avg = (await db.execute(select(func.count(), *[func.avg(getattr(Critique, k)) for k in CRITERIA])
                            .select_from(Critique).join(User, User.id == Critique.user_id).where(_live(photo.id, None)))).one()
    count, values = avg[0] or 0, [round(float(v), 2) if v is not None else None for v in avg[1:]]
    overall = round(sum(values) / 4, 2) if count else None
    items = await _outs(db, rows, photo, viewer)
    my = next((c for c in items if c.mine), None)
    return CritiqueList(count=count, averages=CritiqueAverages(**dict(zip(CRITERIA, values)), overall=overall),
                        items=items, my_critique=my, can_critique=await _can_critique(db, photo, viewer) is None,
                        critique_requested=bool(photo.critique_requested), critique_question=photo.critique_question)


@router.put("/photos/{photo_id}/critiques", response_model=CritiqueOut,
            dependencies=[rate_limit("critique", 30, 3600, by="user")])
async def upsert_critique(photo_id: uuid.UUID, body: CritiqueIn, background: BackgroundTasks,
                          user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    """Eleştirimi oluşturur ya da günceller. İlk oluşturmada fotoğraf sahibine "critique_new" bildirimi gider."""
    photo = await _photo(db, photo_id, user)
    reason = await _can_critique(db, photo, user)
    if reason:
        raise AppError(409 if reason == "critique_not_requested" else 403, reason)
    c = await db.scalar(select(Critique).where(Critique.photo_id == photo.id, Critique.user_id == user.id))
    fields = {**{k: getattr(body, k) for k in CRITERIA},
              "good": (body.good or "").strip() or None, "improve": (body.improve or "").strip() or None}
    n = None
    if c:
        for k, v in fields.items():
            setattr(c, k, v)
    else:
        c = Critique(id=uuid.uuid4(), photo_id=photo.id, user_id=user.id, **fields)
        db.add(c)
        n = await notify(db, user_id=photo.user_id, type="critique_new", actor_id=user.id, photo_id=photo.id,
                         data={"critique_id": str(c.id)}, dedupe=True)
    await db.commit()
    if n:
        background.add_task(deliver, [n.id])
    c = await db.scalar(select(Critique).where(Critique.id == c.id).options(selectinload(Critique.user)))
    [out] = await _outs(db, [c], photo, user)
    return out


@router.delete("/photos/{photo_id}/critiques/me", status_code=204)
async def delete_my_critique(photo_id: uuid.UUID, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    await db.execute(delete(Critique).where(Critique.photo_id == photo_id, Critique.user_id == user.id))
    await db.commit()
    return Response(status_code=204)


async def _critique(db: AsyncSession, critique_id: uuid.UUID, user: User) -> tuple[Critique, Photo]:
    c = await db.get(Critique, critique_id)
    if not c:
        raise AppError(404, "not_found")
    photo = await _photo(db, c.photo_id, user)
    return c, photo


@router.delete("/critiques/{critique_id}", status_code=204)
async def delete_critique(critique_id: uuid.UUID, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    """Eleştiriyi yazan, fotoğrafın sahibi ya da site yöneticisi siler."""
    c = await db.get(Critique, critique_id)
    if not c:
        raise AppError(404, "not_found")
    photo = await db.get(Photo, c.photo_id)
    if user.id not in (c.user_id, photo.user_id) and not user.is_admin:
        raise AppError(403, "forbidden")
    await db.delete(c)
    await db.commit()
    return Response(status_code=204)


@router.post("/critiques/{critique_id}/helpful", status_code=204)
async def mark_helpful(critique_id: uuid.UUID, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    c, _ = await _critique(db, critique_id, user)
    if c.user_id == user.id:
        raise AppError(403, "cannot_mark_own")
    if await _blocked(db, user.id, c.user_id):
        raise AppError(403, "forbidden")
    if not await db.get(CritiqueHelpful, (c.id, user.id)):
        db.add(CritiqueHelpful(critique_id=c.id, user_id=user.id))
        await db.commit()
    return Response(status_code=204)


@router.delete("/critiques/{critique_id}/helpful", status_code=204)
async def unmark_helpful(critique_id: uuid.UUID, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    await db.execute(delete(CritiqueHelpful).where(CritiqueHelpful.critique_id == critique_id,
                                                   CritiqueHelpful.user_id == user.id))
    await db.commit()
    return Response(status_code=204)


@router.get("/critiques/requests", response_model=PhotoPage)
async def critique_requests(cursor: str | None = None, limit: int = Query(20, ge=1, le=50),
                            viewer: User | None = Depends(get_optional_user), db: AsyncSession = Depends(get_db)):
    """"Eleştiri bekleyenler" akışı: eleştiri isteyen yayındaki kareler, en yeni önce (kendi karelerim hariç)."""
    try:
        off = max(0, int(cursor)) if cursor else 0
    except ValueError:
        off = 0
    q = (select(Photo).join(User, User.id == Photo.user_id)
         .where(Photo.status == PhotoStatus.published, Photo.hidden.is_(False), Photo.critique_requested.is_(True),
                *owner_visible(viewer))
         .options(selectinload(Photo.user)))
    if viewer:
        q = q.where(Photo.user_id != viewer.id)
    photos = list(await db.scalars(q.order_by(Photo.published_at.desc(), Photo.id.desc()).offset(off).limit(limit + 1)))
    return PhotoPage(items=await _cards(db, photos[:limit], viewer),
                     next_cursor=str(off + limit) if len(photos) > limit else None)
