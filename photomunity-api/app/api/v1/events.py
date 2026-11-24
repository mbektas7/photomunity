"""Topluluk etkinlikleri (foto yürüyüşü / buluşma). Yöneticiler düzenler, üyeler katılır.

Topluluklar herkese açıktır (gizli topluluk kavramı yok; yalnızca site yönetiminin gizlediği topluluklar 404 döner),
bu yüzden etkinlikler de topluluk gönderileri gibi herkese görünür; katılmak için üyelik gerekir.
"""
import uuid
from datetime import datetime, timedelta

from fastapi import APIRouter, BackgroundTasks, Depends, Query, Response
from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user, get_optional_user
from app.api.v1.communities import _get as get_community, _require_admin, community_cards
from app.core.database import get_db
from app.core.errors import AppError
from app.core.security import as_aware
from app.models import Community, CommunityEvent, CommunityMember, EventAttendee, Notification, User
from app.schemas import EventCard, EventIn, EventList, EventOut, EventUpdate, UserCard
from app.services import themes as tsvc
from app.services.contests import community_role, is_admin_role
from app.services.notifications import deliver, notify
from app.services.ratelimit import rate_limit

router = APIRouter(tags=["events"])
DEFAULT_DURATION = timedelta(hours=3)  # bitişi girilmemiş etkinlik için "sürüyor" penceresi


def utcnow() -> datetime:
    return tsvc.utcnow()


def _end(e: CommunityEvent) -> datetime:
    return as_aware(e.ends_at) if e.ends_at else as_aware(e.starts_at) + DEFAULT_DURATION


def event_status(e: CommunityEvent, now: datetime | None = None) -> str:
    now = now or utcnow()
    if e.cancelled_at:
        return "cancelled"
    if now < as_aware(e.starts_at):
        return "upcoming"
    return "ongoing" if now < _end(e) else "past"


def _data(e: CommunityEvent, c: Community) -> dict:
    return {"event_id": str(e.id), "event": e.title, "community": c.name, "community_slug": c.slug,
            "starts_at": as_aware(e.starts_at).isoformat()}


async def _counts(db: AsyncSession, ids: list[uuid.UUID]) -> dict[uuid.UUID, int]:
    if not ids:
        return {}
    return dict((await db.execute(select(EventAttendee.event_id, func.count()).where(
        EventAttendee.event_id.in_(ids)).group_by(EventAttendee.event_id))).all())


async def event_cards(db: AsyncSession, events: list[CommunityEvent], viewer: User | None) -> list[EventCard]:
    ids = [e.id for e in events]
    counts = await _counts(db, ids)
    mine = set()
    if viewer and ids:
        mine = set(await db.scalars(select(EventAttendee.event_id).where(
            EventAttendee.user_id == viewer.id, EventAttendee.event_id.in_(ids))))
    comms = {c.id: c for c in await db.scalars(select(Community).where(Community.id.in_({e.community_id for e in events})))} if events else {}
    ccards = {c.id: c for c in await community_cards(db, list(comms.values()), viewer)}
    now = utcnow()
    return [EventCard(id=e.id, community=ccards[e.community_id], title=e.title, starts_at=e.starts_at, ends_at=e.ends_at,
                      location_name=e.location_name, latitude=e.latitude, longitude=e.longitude, capacity=e.capacity,
                      attendee_count=counts.get(e.id, 0), attending=e.id in mine, status=event_status(e, now),
                      cancelled_at=e.cancelled_at) for e in events]


async def event_out(db: AsyncSession, e: CommunityEvent, viewer: User | None) -> EventOut:
    [card] = await event_cards(db, [e], viewer)
    preview = list(await db.scalars(select(User).join(EventAttendee, EventAttendee.user_id == User.id).where(
        EventAttendee.event_id == e.id, User.is_active.is_(True)).order_by(EventAttendee.created_at).limit(8)))
    creator = await db.get(User, e.created_by) if e.created_by else None
    role = await community_role(db, e.community_id, viewer.id) if viewer else None
    return EventOut(**card.model_dump(), description=e.description, bring=e.bring,
                    created_by=UserCard.model_validate(creator) if creator else None, created_at=e.created_at,
                    attendees_preview=[UserCard.model_validate(u) for u in preview],
                    my_role=role.value if role else None, can_manage=is_admin_role(role))


async def _event(db: AsyncSession, event_id: uuid.UUID) -> tuple[CommunityEvent, Community]:
    e = await db.get(CommunityEvent, event_id)
    c = await db.get(Community, e.community_id) if e else None
    if not e or not c or c.hidden:
        raise AppError(404, "not_found")
    return e, c


def _check_dates(starts: datetime, ends: datetime | None, require_future: bool) -> None:
    if (require_future and starts <= utcnow()) or (ends is not None and ends <= starts):
        raise AppError(422, "invalid_event_dates")


@router.get("/communities/{slug}/events", response_model=EventList)
async def list_events(slug: str, viewer: User | None = Depends(get_optional_user), db: AsyncSession = Depends(get_db)):
    """Yaklaşan ve süren etkinlikler (en yakın önce) ile geçmiş etkinlikler (en yeni önce, en fazla 50)."""
    c = await get_community(db, slug)
    rows = list(await db.scalars(select(CommunityEvent).where(CommunityEvent.community_id == c.id)
                                 .order_by(CommunityEvent.starts_at.desc()).limit(300)))
    now = utcnow()
    upcoming = sorted((e for e in rows if _end(e) > now), key=lambda e: as_aware(e.starts_at))
    past = [e for e in rows if _end(e) <= now][:50]
    cards = {x.id: x for x in await event_cards(db, upcoming + past, viewer)}
    return EventList(upcoming=[cards[e.id] for e in upcoming], past=[cards[e.id] for e in past])


@router.get("/me/events", response_model=list[EventCard])
async def my_events(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    """Katılacağımı bildirdiğim, henüz bitmemiş etkinlikler (en yakın önce)."""
    rows = list(await db.scalars(select(CommunityEvent).join(EventAttendee, EventAttendee.event_id == CommunityEvent.id)
                                 .join(Community, Community.id == CommunityEvent.community_id)
                                 .where(EventAttendee.user_id == user.id, Community.hidden.is_(False),
                                        CommunityEvent.starts_at >= utcnow() - timedelta(days=2))
                                 .order_by(CommunityEvent.starts_at).limit(100)))
    now = utcnow()
    return await event_cards(db, [e for e in rows if _end(e) > now], user)


@router.post("/communities/{slug}/events", response_model=EventOut, status_code=201,
             dependencies=[rate_limit("event_create", 20, 86400, by="user")])
async def create_event(slug: str, body: EventIn, background: BackgroundTasks, user: User = Depends(get_current_user),
                       db: AsyncSession = Depends(get_db)):
    """Topluluk sahibi/yöneticisi oluşturur; diğer üyelere "event_new" bildirimi gider."""
    c = await get_community(db, slug)
    await _require_admin(db, c, user)
    starts = tsvc.to_utc(body.starts_at)
    ends = tsvc.to_utc(body.ends_at) if body.ends_at else None
    _check_dates(starts, ends, require_future=True)
    e = CommunityEvent(id=uuid.uuid4(), community_id=c.id, title=body.title.strip(),
                       description=(body.description or "").strip() or None, starts_at=starts, ends_at=ends,
                       location_name=body.location_name.strip(), latitude=body.latitude, longitude=body.longitude,
                       capacity=body.capacity, bring=(body.bring or "").strip() or None, created_by=user.id)
    db.add(e)
    created: list[Notification] = []
    for uid in await db.scalars(select(CommunityMember.user_id).where(CommunityMember.community_id == c.id)):
        n = await notify(db, user_id=uid, type="event_new", actor_id=user.id, data=_data(e, c))
        if n:
            created.append(n)
    await db.commit()
    if created:
        background.add_task(deliver, [n.id for n in created])
    return await event_out(db, e, user)


@router.get("/events/{event_id}", response_model=EventOut)
async def get_event(event_id: uuid.UUID, viewer: User | None = Depends(get_optional_user), db: AsyncSession = Depends(get_db)):
    e, _ = await _event(db, event_id)
    return await event_out(db, e, viewer)


@router.patch("/events/{event_id}", response_model=EventOut)
async def update_event(event_id: uuid.UUID, body: EventUpdate, user: User = Depends(get_current_user),
                       db: AsyncSession = Depends(get_db)):
    e, c = await _event(db, event_id)
    await _require_admin(db, c, user)
    if e.cancelled_at or event_status(e) == "past":
        raise AppError(409, "event_closed")
    data = body.model_dump(exclude_unset=True)
    starts = tsvc.to_utc(data["starts_at"]) if data.get("starts_at") else as_aware(e.starts_at)
    ends = tsvc.to_utc(data["ends_at"]) if data.get("ends_at") else (None if "ends_at" in data else e.ends_at and as_aware(e.ends_at))
    if "starts_at" in data or "ends_at" in data:
        _check_dates(starts, ends, require_future="starts_at" in data and starts != as_aware(e.starts_at))
        if starts != as_aware(e.starts_at):
            e.reminder_sent = False  # tarih değiştiyse hatırlatma yeni tarihe göre tekrar gider
        e.starts_at, e.ends_at = starts, ends
    if "capacity" in data and data["capacity"] is not None:
        if data["capacity"] < (await _counts(db, [e.id])).get(e.id, 0):
            raise AppError(422, "capacity_too_low")
    for k in ("title", "location_name"):
        if data.get(k):
            setattr(e, k, data[k].strip())
    for k in ("description", "bring"):
        if k in data:
            setattr(e, k, (data[k] or "").strip() or None)
    for k in ("latitude", "longitude", "capacity"):
        if k in data:
            setattr(e, k, data[k])
    await db.commit()
    return await event_out(db, e, user)


@router.post("/events/{event_id}/cancel", response_model=EventOut)
async def cancel_event(event_id: uuid.UUID, background: BackgroundTasks, user: User = Depends(get_current_user),
                       db: AsyncSession = Depends(get_db)):
    """İptal eder ve katılacağını bildirenlere "event_cancelled" gönderir. Tekrar çağrı bir şey yapmaz."""
    e, c = await _event(db, event_id)
    await _require_admin(db, c, user)
    created: list[Notification] = []
    if not e.cancelled_at:
        e.cancelled_at = utcnow()
        for uid in await db.scalars(select(EventAttendee.user_id).where(EventAttendee.event_id == e.id)):
            n = await notify(db, user_id=uid, type="event_cancelled", actor_id=user.id, data=_data(e, c))
            if n:
                created.append(n)
        await db.commit()
    if created:
        background.add_task(deliver, [n.id for n in created])
    return await event_out(db, e, user)


@router.post("/events/{event_id}/attend", response_model=EventOut)
async def attend(event_id: uuid.UUID, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    e, c = await _event(db, event_id)
    if await community_role(db, c.id, user.id) is None:
        raise AppError(403, "not_member")
    if event_status(e) in ("cancelled", "past"):
        raise AppError(409, "event_closed")
    if not await db.get(EventAttendee, (e.id, user.id)):
        if e.capacity is not None and (await _counts(db, [e.id])).get(e.id, 0) >= e.capacity:
            raise AppError(409, "event_full")
        db.add(EventAttendee(event_id=e.id, user_id=user.id))
        await db.commit()
    return await event_out(db, e, user)


@router.delete("/events/{event_id}/attend", status_code=204)
async def unattend(event_id: uuid.UUID, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    await db.execute(delete(EventAttendee).where(EventAttendee.event_id == event_id, EventAttendee.user_id == user.id))
    await db.commit()
    return Response(status_code=204)


@router.get("/events/{event_id}/attendees", response_model=list[UserCard])
async def attendees(event_id: uuid.UUID, limit: int = Query(500, ge=1, le=1000), db: AsyncSession = Depends(get_db)):
    """Katılacağını bildirenler, bildirim sırasına göre."""
    e, _ = await _event(db, event_id)
    rows = await db.scalars(select(User).join(EventAttendee, EventAttendee.user_id == User.id).where(
        EventAttendee.event_id == e.id, User.is_active.is_(True)).order_by(EventAttendee.created_at).limit(limit))
    return [UserCard.model_validate(u) for u in rows]


async def send_event_reminders(db: AsyncSession) -> list[Notification]:
    """Worker: başlamasına 24 saatten az kalan etkinliklerin katılımcılarına bir kez "event_reminder". Commit çağırana aittir."""
    now = utcnow()
    created: list[Notification] = []
    rows = list(await db.scalars(select(CommunityEvent).where(
        CommunityEvent.cancelled_at.is_(None), CommunityEvent.reminder_sent.is_(False),
        CommunityEvent.starts_at > now, CommunityEvent.starts_at <= now + timedelta(hours=24))))
    for e in rows:
        c = await db.get(Community, e.community_id)
        e.reminder_sent = True
        if not c or c.hidden:
            continue
        for uid in await db.scalars(select(EventAttendee.user_id).where(EventAttendee.event_id == e.id)):
            n = await notify(db, user_id=uid, type="event_reminder", data=_data(e, c))
            if n:
                created.append(n)
    return created
