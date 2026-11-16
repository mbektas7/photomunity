from datetime import datetime

from fastapi import APIRouter, Depends, Query, Request, Response
from sqlalchemy import delete, func, select, update
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.api.deps import get_current_user
from app.core.database import get_db
from app.core.errors import request_locale
from app.core.security import utcnow
from app.models import DeviceToken, Notification, User
from app.schemas import DeviceIn, MarkReadIn, NotificationOut, NotificationPage, NotificationPhoto, NotificationSettings, UserCard
from app.services import storage
from app.services.notifications import PUSH_DEFAULTS, render

router = APIRouter(tags=["notifications"])


async def _unread(db: AsyncSession, user_id) -> int:
    return await db.scalar(select(func.count()).select_from(Notification)
                           .where(Notification.user_id == user_id, Notification.read_at.is_(None))) or 0


@router.get("/notifications", response_model=NotificationPage)
async def list_notifications(request: Request, before: datetime | None = None, limit: int = Query(30, le=100),
                             user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    q = (select(Notification).where(Notification.user_id == user.id)
         .options(selectinload(Notification.actor), selectinload(Notification.photo)))
    if before:
        q = q.where(Notification.created_at < before)
    rows = list(await db.scalars(q.order_by(Notification.created_at.desc()).limit(limit + 1)))
    locale = request_locale(request)
    items = []
    for n in rows[:limit]:
        photo = None
        if n.photo is not None:
            thumb = (n.photo.variants or {}).get("thumb")
            photo = NotificationPhoto(id=n.photo.id, thumb_url=storage.public_url(thumb["key"]) if thumb else None)
        items.append(NotificationOut(
            id=n.id, type=n.type, text=render(n, locale), data=n.data or {}, read=n.read_at is not None,
            actor=UserCard.model_validate(n.actor) if n.actor else None, photo=photo, created_at=n.created_at,
        ))
    cursor = rows[limit - 1].created_at.isoformat() if len(rows) > limit else None
    return NotificationPage(items=items, next_cursor=cursor, unread_count=await _unread(db, user.id))


@router.get("/notifications/unread-count")
async def unread_count(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    return {"count": await _unread(db, user.id)}


@router.post("/notifications/read", status_code=204)
async def mark_read(body: MarkReadIn, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    q = update(Notification).where(Notification.user_id == user.id, Notification.read_at.is_(None))
    if body.ids:
        q = q.where(Notification.id.in_(body.ids))
    await db.execute(q.values(read_at=utcnow()))
    await db.commit()
    return Response(status_code=204)


@router.post("/devices", status_code=204)
async def register_device(body: DeviceIn, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    """Aynı token başka bir hesaba bağlıysa (cihazda hesap değişti) bu hesaba taşınır."""
    existing = await db.get(DeviceToken, body.token)
    if existing:
        existing.user_id, existing.platform = user.id, body.platform
    else:
        db.add(DeviceToken(token=body.token, user_id=user.id, platform=body.platform))
    await db.commit()
    return Response(status_code=204)


@router.delete("/devices/{token}", status_code=204)
async def unregister_device(token: str, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    await db.execute(delete(DeviceToken).where(DeviceToken.token == token, DeviceToken.user_id == user.id))
    await db.commit()
    return Response(status_code=204)


def _settings(user: User) -> NotificationSettings:
    saved = (user.notification_prefs or {}).get("push", {})
    return NotificationSettings(push={k: bool(saved.get(k, v)) for k, v in PUSH_DEFAULTS.items()})


@router.get("/me/notification-settings", response_model=NotificationSettings)
async def get_settings_(user: User = Depends(get_current_user)):
    return _settings(user)


@router.patch("/me/notification-settings", response_model=NotificationSettings)
async def update_settings(body: NotificationSettings, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    push = {**(user.notification_prefs or {}).get("push", {})}
    push.update({k: bool(v) for k, v in body.push.items() if k in PUSH_DEFAULTS})
    user.notification_prefs = {**(user.notification_prefs or {}), "push": push}
    await db.commit()
    return _settings(user)
