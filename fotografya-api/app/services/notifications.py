"""Bildirim oluşturma ve teslim (uygulama içi kayıt + tercihe bağlı push)."""
import logging
import uuid

from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core import database
from app.models import DeviceToken, Notification, User
from app.services.push import get_fcm

log = logging.getLogger("fotografya.notifications")

# Push varsayılanları (kullanıcı ayarlardan değiştirebilir). Uygulama içi bildirim her zaman oluşturulur.
PUSH_DEFAULTS: dict[str, bool] = {
    "new_follower": True,
    "photo_liked": False,
    "photo_published": True,
    "photo_rejected": True,
    "community_admin_invite": True,
    "contest_new": True,
    "contest_deadline": True,
    "contest_judge_invite": True,
    "contest_results": True,
    "contest_entry_disqualified": True,
    "new_message": True,
    "message_request": True,
}

TEXT: dict[str, dict[str, str]] = {
    "new_follower": {"tr": "{actor} seni takip etmeye başladı.", "en": "{actor} started following you."},
    "photo_liked": {"tr": "{actor} fotoğrafını beğendi.", "en": "{actor} liked your photo."},
    "photo_published": {"tr": "Fotoğrafın yayınlandı.", "en": "Your photo is published."},
    "photo_rejected": {"tr": "Fotoğrafın yayınlanamadı. Sebebini görmek için dokun.", "en": "Your photo couldn't be published. Tap to see why."},
    "community_admin_invite": {"tr": "{actor} seni {community} topluluğuna yönetici olarak ekledi.", "en": "{actor} made you an admin of {community}."},
    "contest_new": {"tr": "{community} yeni bir yarışma açtı: {contest}", "en": "{community} opened a new contest: {contest}"},
    "contest_deadline": {"tr": "{contest} için son gönderim yarın.", "en": "Submissions for {contest} close tomorrow."},
    "contest_judge_invite": {"tr": "{contest} yarışmasında jüri olarak davet edildin.", "en": "You're invited to judge {contest}."},
    "contest_results": {"tr": "{contest} sonuçlandı.", "en": "Results are out for {contest}."},
    "contest_won": {"tr": "Tebrikler! {contest} yarışmasında {rank}. oldun.", "en": "Congratulations! You placed #{rank} in {contest}."},
    "contest_entry_disqualified": {"tr": "{contest} yarışmasındaki katılımın geçersiz sayıldı.", "en": "Your entry in {contest} was disqualified."},
    "new_message": {"tr": "{actor}: {preview}", "en": "{actor}: {preview}"},
    "message_request": {"tr": "{actor} sana mesaj göndermek istiyor.", "en": "{actor} wants to send you a message."},
}


def render(n: Notification, locale: str) -> str:
    template = TEXT.get(n.type, {}).get(locale) or TEXT.get(n.type, {}).get("en") or n.type
    params = {"actor": n.actor.display_name if n.actor else "", **{k: str(v) for k, v in (n.data or {}).items()}}
    try:
        return template.format(**params)
    except KeyError:
        return template


def push_enabled(user: User, type_: str) -> bool:
    prefs = (user.notification_prefs or {}).get("push", {})
    return bool(prefs.get(type_, PUSH_DEFAULTS.get(type_, True)))


async def notify(
    db: AsyncSession,
    *,
    user_id: uuid.UUID,
    type: str,
    actor_id: uuid.UUID | None = None,
    photo_id: uuid.UUID | None = None,
    data: dict | None = None,
    dedupe: bool = False,
) -> Notification | None:
    """Bildirimi oturuma ekler (commit çağırana aittir). Kişi kendi eylemi için bildirim almaz."""
    if actor_id is not None and actor_id == user_id:
        return None
    if dedupe:
        exists = await db.scalar(select(Notification.id).where(
            Notification.user_id == user_id, Notification.type == type,
            Notification.actor_id == actor_id, Notification.photo_id == photo_id))
        if exists:
            return None
    n = Notification(id=uuid.uuid4(), user_id=user_id, type=type, actor_id=actor_id, photo_id=photo_id, data=data or {})
    db.add(n)
    return n


async def deliver(notification_ids: list[uuid.UUID]) -> None:
    """Commit sonrası arka planda çağrılır: alıcının tercihine göre push gönderir."""
    if not notification_ids:
        return
    fcm = get_fcm()
    async with database.SessionLocal() as db:
        rows = await db.scalars(select(Notification).where(Notification.id.in_(notification_ids))
                                .options(selectinload(Notification.actor)))
        for n in rows:
            user = await db.get(User, n.user_id)
            if not user or not user.is_active or not push_enabled(user, n.type):
                continue
            tokens = list(await db.scalars(select(DeviceToken.token).where(DeviceToken.user_id == user.id)))
            if not tokens:
                continue
            body = render(n, user.locale)
            data = {"type": n.type, "notification_id": str(n.id)}
            if n.photo_id:
                data["photo_id"] = str(n.photo_id)
            if n.actor:
                data["username"] = n.actor.username
            for k in ("community_slug", "contest_id"):
                if k in (n.data or {}):
                    data[k] = str(n.data[k])
            if fcm is None:
                log.info("push (dev) -> %s: %s %s", user.username, body, data)
                continue
            invalid = [t for t in tokens if not await fcm.send(t, "Fotografya", body, data)]
            if invalid:
                await db.execute(delete(DeviceToken).where(DeviceToken.token.in_(invalid)))
        await db.commit()


async def push_direct(user_id: uuid.UUID, type_: str, actor_name: str, data: dict[str, str], params: dict | None = None) -> None:
    """Bildirim listesine yazılmayan anlık push (mesajlar gibi). Tercih ve cihaz kontrolü deliver() ile aynıdır."""
    fcm = get_fcm()
    async with database.SessionLocal() as db:
        user = await db.get(User, user_id)
        if not user or not user.is_active or not push_enabled(user, type_):
            return
        tokens = list(await db.scalars(select(DeviceToken.token).where(DeviceToken.user_id == user.id)))
        if not tokens:
            return
        template = TEXT[type_].get(user.locale) or TEXT[type_]["en"]
        body = template.format(actor=actor_name, **(params or {}))
        if fcm is None:
            log.info("push (dev) -> %s: %s %s", user.username, body, data)
            return
        invalid = [t for t in tokens if not await fcm.send(t, "Fotografya", body, {"type": type_, **data})]
        if invalid:
            await db.execute(delete(DeviceToken).where(DeviceToken.token.in_(invalid)))
            await db.commit()
