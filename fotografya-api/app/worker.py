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
        due = await db.scalars(select(Contest).where(Contest.published_at.is_not(None), Contest.finalized_at.is_(None),
                                                     Contest.results_at <= now))
        for c in due:
            created += await finalize_if_due(db, c)
        soon = await db.scalars(select(Contest).options(selectinload(Contest.community)).where(
            Contest.published_at.is_not(None), Contest.deadline_reminder_sent.is_(False),
            Contest.submission_deadline > now, Contest.submission_deadline <= now + timedelta(hours=24)))
        for c in soon:
            created += await notify_members(db, c, c.community.name, "contest_deadline", exclude_entrants=True)
            c.deadline_reminder_sent = True
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
    ]
    redis_settings = RedisSettings.from_dsn(get_settings().redis_url)
    max_jobs = 4
    job_timeout = 300
