"""Çekim planları (Samanyolu, altın saat ...): hatırlatma ve hava uyarısı worker'da.

/me/plans: kişinin kendi planları. /plans: takip edilenlerin paylaştığı planlar, plan ayrıntısı ve katılım.
"""
import uuid
from collections import defaultdict
from typing import Literal

from fastapi import APIRouter, BackgroundTasks, Depends, Query, Response
from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user, not_blocked, owner_visible
from app.core.database import get_db
from app.core.errors import AppError
from app.core.security import as_aware
from app.models import Follow, PlanJoin, ShootPlan, User
from app.schemas import PlanIn, PlanOut, PlanPage, PlanUpdate, SharedPlanOut, SharedPlanPage, UserCard
from app.services import plans as svc
from app.services.notifications import deliver, notify
from app.services.ratelimit import rate_limit
from app.services.themes import to_utc

router = APIRouter(prefix="/me/plans", tags=["plans"])
shared_router = APIRouter(prefix="/plans", tags=["plans"])
MAX_UPCOMING = 100
JOINERS_PREVIEW = 8


def _status(p: ShootPlan) -> str:
    return "upcoming" if as_aware(p.target_at) > svc.utcnow() else "past"


async def _join_info(db: AsyncSession, plan_ids: list[uuid.UUID], viewer: User) -> tuple[dict, dict, set]:
    """Plan başına katılımcı sayısı, en yeni 8 katılımcı ve izleyicinin katıldığı planlar.
    Yalnızca aktif hesaplar sayılır; izleyiciyle arasında engel olanlar listelenmez (sayıya dahildir)."""
    if not plan_ids:
        return {}, {}, set()
    counts = dict((await db.execute(
        select(PlanJoin.plan_id, func.count()).join(User, User.id == PlanJoin.user_id)
        .where(PlanJoin.plan_id.in_(plan_ids), User.is_active.is_(True)).group_by(PlanJoin.plan_id))).all())
    rows = (await db.execute(
        select(PlanJoin.plan_id, User).join(User, User.id == PlanJoin.user_id)
        .where(PlanJoin.plan_id.in_(plan_ids), User.is_active.is_(True), *not_blocked(User.id, viewer))
        .order_by(PlanJoin.created_at.desc()))).all()
    preview: dict[uuid.UUID, list[UserCard]] = defaultdict(list)
    for pid, u in rows:
        if len(preview[pid]) < JOINERS_PREVIEW:
            preview[pid].append(UserCard.model_validate(u))
    mine = set(await db.scalars(select(PlanJoin.plan_id).where(PlanJoin.plan_id.in_(plan_ids),
                                                               PlanJoin.user_id == viewer.id)))
    return counts, preview, mine


async def _outs(db: AsyncSession, plans: list[ShootPlan], user: User) -> list[PlanOut]:
    counts, preview, _ = await _join_info(db, [p.id for p in plans], user)
    out = []
    for p in plans:
        o = PlanOut.model_validate(p)
        o.status = _status(p)
        o.join_count, o.joiners = counts.get(p.id, 0), preview.get(p.id, [])
        out.append(o)
    return out


async def _out(db: AsyncSession, p: ShootPlan, user: User) -> PlanOut:
    return (await _outs(db, [p], user))[0]


async def _shared_outs(db: AsyncSession, rows: list[tuple[ShootPlan, User]], viewer: User) -> list[SharedPlanOut]:
    counts, preview, mine = await _join_info(db, [p.id for p, _ in rows], viewer)
    return [SharedPlanOut(
        id=p.id, kind=p.kind, title=p.title, latitude=p.latitude, longitude=p.longitude, place_name=p.place_name,
        target_at=p.target_at, notes=p.notes, owner=UserCard.model_validate(owner), join_count=counts.get(p.id, 0),
        joined=p.id in mine, joiners=preview.get(p.id, []), status=_status(p)) for p, owner in rows]


async def _own(db: AsyncSession, plan_id: uuid.UUID, user: User) -> ShootPlan:
    p = await db.get(ShootPlan, plan_id)
    if not p or p.user_id != user.id:
        raise AppError(404, "not_found")
    return p


async def _upcoming_count(db: AsyncSession, user: User) -> int:
    return await db.scalar(select(func.count()).select_from(ShootPlan).where(
        ShootPlan.user_id == user.id, ShootPlan.target_at > svc.utcnow())) or 0


@router.get("", response_model=PlanPage)
async def list_plans(scope: Literal["upcoming", "past"] = "upcoming", cursor: str | None = None,
                     limit: int = Query(50, ge=1, le=100), user: User = Depends(get_current_user),
                     db: AsyncSession = Depends(get_db)):
    """upcoming: hedef zamanı gelmemiş, en yakın önce. past: geçmiş, en yeni önce."""
    try:
        off = max(0, int(cursor)) if cursor else 0
    except ValueError:
        off = 0
    now = svc.utcnow()
    q = select(ShootPlan).where(ShootPlan.user_id == user.id)
    q = (q.where(ShootPlan.target_at > now).order_by(ShootPlan.target_at.asc()) if scope == "upcoming"
         else q.where(ShootPlan.target_at <= now).order_by(ShootPlan.target_at.desc()))
    rows = list(await db.scalars(q.offset(off).limit(limit + 1)))
    return PlanPage(items=await _outs(db, rows[:limit], user), next_cursor=str(off + limit) if len(rows) > limit else None)


@router.post("", response_model=PlanOut, status_code=201)
async def create_plan(body: PlanIn, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    target = to_utc(body.target_at)
    if target <= svc.utcnow():
        raise AppError(422, "invalid_plan_date")
    if await _upcoming_count(db, user) >= MAX_UPCOMING:
        raise AppError(409, "plan_limit")
    p = ShootPlan(id=uuid.uuid4(), user_id=user.id, kind=body.kind, title=(body.title or "").strip() or None,
                  latitude=body.latitude, longitude=body.longitude, place_name=(body.place_name or "").strip() or None,
                  target_at=target, remind=body.remind, weather_alert=body.weather_alert,
                  notes=(body.notes or "").strip() or None, shared=body.shared, created_at=svc.utcnow())
    svc.preset_reminders(p)
    db.add(p)
    await db.commit()
    return await _out(db, p, user)


@router.get("/{plan_id}", response_model=PlanOut)
async def get_plan(plan_id: uuid.UUID, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    return await _out(db, await _own(db, plan_id, user), user)


@router.patch("/{plan_id}", response_model=PlanOut)
async def update_plan(plan_id: uuid.UUID, body: PlanUpdate, user: User = Depends(get_current_user),
                      db: AsyncSession = Depends(get_db)):
    """target_at ya da konum değişirse hatırlatma ve hava uyarısı yeni değerlere göre sıfırlanır."""
    p = await _own(db, plan_id, user)
    data = body.model_dump(exclude_unset=True)
    reset = False
    if data.get("target_at"):
        target = to_utc(data.pop("target_at"))
        if target != as_aware(p.target_at):
            if target <= svc.utcnow():
                raise AppError(422, "invalid_plan_date")
            if as_aware(p.target_at) <= svc.utcnow() and await _upcoming_count(db, user) >= MAX_UPCOMING:
                raise AppError(409, "plan_limit")
            p.target_at, reset = target, True
    data.pop("target_at", None)
    for k in ("latitude", "longitude"):
        if data.get(k) is not None and data[k] != getattr(p, k):
            setattr(p, k, data[k])
            reset = True
        data.pop(k, None)
    for k in ("title", "place_name", "notes"):
        if k in data:
            setattr(p, k, (data.pop(k) or "").strip() or None)
    for k, v in data.items():
        if v is not None:
            setattr(p, k, v)
    if not p.shared:  # paylaşım kapatılınca katılımlar silinir
        await db.execute(delete(PlanJoin).where(PlanJoin.plan_id == p.id))
    if reset:
        svc.preset_reminders(p)
        p.last_cloud_cover = p.weather_checked_at = None
        if p.shared:
            await svc.reset_join_reminders(db, p)
    await db.commit()
    return await _out(db, p, user)


@router.delete("/{plan_id}", status_code=204)
async def delete_plan(plan_id: uuid.UUID, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    p = await _own(db, plan_id, user)
    await db.execute(delete(PlanJoin).where(PlanJoin.plan_id == p.id))
    await db.delete(p)
    await db.commit()
    return Response(status_code=204)


# ---------------------------------------------------------------- paylaşılan planlar
def _with_owner(viewer: User):
    return (select(ShootPlan, User).join(User, User.id == ShootPlan.user_id).where(*owner_visible(viewer)))


async def _visible(db: AsyncSession, plan_id: uuid.UUID, viewer: User, require_shared: bool = True) -> tuple[ShootPlan, User]:
    """Kendi planım ya da (paylaşılmış ve) sahibi görünür, aralarında engel olmayan plan; değilse 404."""
    row = (await db.execute(_with_owner(viewer).where(ShootPlan.id == plan_id))).first()
    if not row:
        raise AppError(404, "not_found")
    p, owner = row
    if require_shared and not p.shared and owner.id != viewer.id:
        raise AppError(404, "not_found")
    return p, owner


@shared_router.get("/shared", response_model=SharedPlanPage)
async def shared_plans(cursor: str | None = None, limit: int = Query(20, ge=1, le=50),
                       user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    """Takip ettiklerimin paylaştığı yaklaşan planlar, en yakın önce (kendi planlarım hariç)."""
    try:
        off = max(0, int(cursor)) if cursor else 0
    except ValueError:
        off = 0
    followees = select(Follow.followee_id).where(Follow.follower_id == user.id)
    q = _with_owner(user).where(ShootPlan.shared.is_(True), ShootPlan.target_at > svc.utcnow(),
                                ShootPlan.user_id != user.id, ShootPlan.user_id.in_(followees))
    rows = [tuple(r) for r in (await db.execute(
        q.order_by(ShootPlan.target_at.asc(), ShootPlan.id).offset(off).limit(limit + 1))).all()]
    return SharedPlanPage(items=await _shared_outs(db, rows[:limit], user),
                          next_cursor=str(off + limit) if len(rows) > limit else None)


@shared_router.get("/{plan_id}", response_model=SharedPlanOut)
async def shared_plan(plan_id: uuid.UUID, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    return (await _shared_outs(db, [await _visible(db, plan_id, user)], user))[0]


@shared_router.post("/{plan_id}/join", response_model=SharedPlanOut,
                    dependencies=[rate_limit("plan_join", 60, 3600, by="user")])
async def join_plan(plan_id: uuid.UUID, background: BackgroundTasks, user: User = Depends(get_current_user),
                    db: AsyncSession = Depends(get_db)):
    """Tekrar çağrılırsa değişiklik yapmaz. Sahibine her yeni katılımda bir kez "plan_join" bildirimi."""
    p, owner = await _visible(db, plan_id, user, require_shared=False)
    if owner.id == user.id:
        raise AppError(403, "cannot_join_own")
    if not p.shared:
        raise AppError(409, "plan_not_shared")
    if not await db.get(PlanJoin, (p.id, user.id)):
        if _status(p) == "past":
            raise AppError(409, "plan_past")
        j = PlanJoin(plan_id=p.id, user_id=user.id)
        svc.preset_join_reminders(j, p)
        db.add(j)
        labels = svc._labels(p)
        n = await notify(db, user_id=owner.id, type="plan_join", actor_id=user.id,
                         data={"plan_id": str(p.id), **labels, "place": p.place_name or ""})
        await db.commit()
        if n:
            background.add_task(deliver, [n.id])
    return (await _shared_outs(db, [(p, owner)], user))[0]


@shared_router.delete("/{plan_id}/join", status_code=204)
async def leave_plan(plan_id: uuid.UUID, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    await db.execute(delete(PlanJoin).where(PlanJoin.plan_id == plan_id, PlanJoin.user_id == user.id))
    await db.commit()
    return Response(status_code=204)
