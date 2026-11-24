"""Kişisel çekim planları (Samanyolu, altın saat ...): hatırlatma ve hava uyarısı worker'da."""
import uuid
from typing import Literal

from fastapi import APIRouter, Depends, Query, Response
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.core.database import get_db
from app.core.errors import AppError
from app.core.security import as_aware
from app.models import ShootPlan, User
from app.schemas import PlanIn, PlanOut, PlanPage, PlanUpdate
from app.services import plans as svc
from app.services.themes import to_utc

router = APIRouter(prefix="/me/plans", tags=["plans"])
MAX_UPCOMING = 100


def _out(p: ShootPlan) -> PlanOut:
    out = PlanOut.model_validate(p)
    out.status = "upcoming" if as_aware(p.target_at) > svc.utcnow() else "past"
    return out


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
    return PlanPage(items=[_out(p) for p in rows[:limit]], next_cursor=str(off + limit) if len(rows) > limit else None)


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
                  notes=(body.notes or "").strip() or None, created_at=svc.utcnow())
    svc.preset_reminders(p)
    db.add(p)
    await db.commit()
    return _out(p)


@router.get("/{plan_id}", response_model=PlanOut)
async def get_plan(plan_id: uuid.UUID, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    return _out(await _own(db, plan_id, user))


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
    if reset:
        svc.preset_reminders(p)
        p.last_cloud_cover = p.weather_checked_at = None
    await db.commit()
    return _out(p)


@router.delete("/{plan_id}", status_code=204)
async def delete_plan(plan_id: uuid.UUID, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    await db.delete(await _own(db, plan_id, user))
    await db.commit()
    return Response(status_code=204)
