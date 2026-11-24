"""ARQ worker: `arq app.worker.WorkerSettings`"""
import uuid
from datetime import timedelta

from arq import cron
from arq.connections import RedisSettings
from sqlalchemy import select
from sqlalchemy.orm import selectinload

from app.core import database
from app.core.config import get_settings
from app.core.security import utcnow
from app.models import Contest, Subscription, User
from app.services.contests import finalize_if_due, notify_members
from app.services.notifications import deliver
from app.services.photo_pipeline import process_photo


async def process_photo_job(ctx, photo_id: str):
    return await process_photo(uuid.UUID(photo_id))


async def contest_tick(ctx):
    """Her 5 dakikada: sonuç tarihi gelen yarışmaları sonuçlandırır, son günü yaklaşanlar için hatırlatır."""
    now = utcnow()
    async with database.SessionLocal() as db:
        created = []
        due = await db.scalars(select(Contest).where(Contest.published_at.is_not(None), Contest.finalized_at.is_(None), Contest.cancelled_at.is_(None),
                                                     Contest.results_at <= now))
        for c in due:
            created += await finalize_if_due(db, c)
        soon = await db.scalars(select(Contest).options(selectinload(Contest.community)).where(
            Contest.published_at.is_not(None), Contest.hidden.is_(False), Contest.deadline_reminder_sent.is_(False),
            Contest.submission_deadline > now, Contest.submission_deadline <= now + timedelta(hours=24)))
        for c in soon:
            created += await notify_members(db, c, c.community.name, "contest_deadline", exclude_entrants=True)
            c.deadline_reminder_sent = True
        await db.commit()
    await deliver([n.id for n in created])


async def theme_tick(ctx):
    """Her 5 dakikada: bitiş zamanı geçen haftalık temaların kazananını belirler."""
    from app.models import WeeklyTheme
    from app.services.themes import finalize_theme

    now = utcnow()
    async with database.SessionLocal() as db:
        created = []
        for t in await db.scalars(select(WeeklyTheme).where(WeeklyTheme.finalized_at.is_(None), WeeklyTheme.ends_at <= now)):
            created += await finalize_theme(db, t)
        await db.commit()
    await deliver([n.id for n in created])


async def reminder_tick(ctx):
    """Her 5 dakikada: etkinlik (24 sa önce) ve çekim planı (24 sa ve 2 sa önce) hatırlatmaları. Bayraklarla tek sefer."""
    from app.api.v1.events import send_event_reminders
    from app.services.plans import send_plan_reminders

    async with database.SessionLocal() as db:
        created = await send_event_reminders(db) + await send_plan_reminders(db)
        await db.commit()
    await deliver([n.id for n in created])


async def plan_weather_tick(ctx):
    """Saatte bir: 48 saat içindeki, hava uyarısı açık planlar için Open-Meteo bulut kontrolü."""
    from app.services.plans import check_plan_weather

    async with database.SessionLocal() as db:
        created = await check_plan_weather(db)
        await db.commit()
    await deliver([n.id for n in created])


async def subscription_tick(ctx):
    """Saatte bir: dönemi bitmiş ama webhook'u gelmemiş abonelikleri kapatır, Pro durumunu yeniden hesaplar."""
    from app.services.billing import recompute_pro

    now = utcnow()
    async with database.SessionLocal() as db:
        stale = await db.scalars(select(Subscription.user_id).where(
            Subscription.status.in_(("active", "grace", "cancelled")), Subscription.period_end <= now).distinct())
        pros_without = await db.scalars(select(User.id).where(User.is_pro.is_(True), User.id.not_in(select(Subscription.user_id))))
        for user_id in {*stale, *pros_without}:
            await recompute_pro(db, user_id)
        await db.commit()


class WorkerSettings:
    functions = [process_photo_job]
    cron_jobs = [
        cron(contest_tick, minute=set(range(0, 60, 5)), run_at_startup=True),
        cron(subscription_tick, minute={17}),
        cron(theme_tick, minute=set(range(1, 60, 5))),
        cron(reminder_tick, minute=set(range(2, 60, 5))),
        cron(plan_weather_tick, minute={23}),
    ]
    redis_settings = RedisSettings.from_dsn(get_settings().redis_url)
    max_jobs = 4
    job_timeout = 300
