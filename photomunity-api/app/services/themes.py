"""Haftalık tema kuralları: durum ve sonuçlandırma (en çok beğenilen kare kazanır)."""
from datetime import datetime, timezone

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import as_aware, utcnow
from app.models import Like, Notification, Photo, PhotoStatus, ThemeEntry, User, WeeklyTheme
from app.services.notifications import notify


def to_utc(dt: datetime) -> datetime:
    """İstemciden gelen zamanı UTC'ye çevirir (SQLite zaman dilimi tutmaz; Postgres'te de tutarlı kalır)."""
    return dt.astimezone(timezone.utc) if dt.tzinfo else dt.replace(tzinfo=timezone.utc)


def theme_status(t: WeeklyTheme, now: datetime | None = None) -> str:
    """scheduled → active → ended (sonuç bekleniyor) → finished."""
    now = now or utcnow()
    if t.finalized_at is not None:
        return "finished"
    if now < as_aware(t.starts_at):
        return "scheduled"
    if now < as_aware(t.ends_at):
        return "active"
    return "ended"


def like_counts_subquery():
    return select(Like.photo_id, func.count().label("n")).group_by(Like.photo_id).subquery()


def eligible_entries(theme_id):
    """Sıralamaya giren katılımlar: kare yayında, gizlenmemiş, sahibi aktif."""
    return (select(ThemeEntry).join(Photo, Photo.id == ThemeEntry.photo_id).join(User, User.id == Photo.user_id)
            .where(ThemeEntry.theme_id == theme_id, Photo.status == PhotoStatus.published, Photo.hidden.is_(False),
                   User.is_active.is_(True)))


async def entry_count(db: AsyncSession, theme_id) -> int:
    return await db.scalar(select(func.count()).select_from(eligible_entries(theme_id).subquery())) or 0


async def finalize_theme(db: AsyncSession, theme: WeeklyTheme) -> list[Notification]:
    """Bitiş zamanı geçtiyse kazananı (en az 1 beğeni, eşitlikte erken katılan) belirler. Commit çağırana aittir."""
    if theme.finalized_at is not None or utcnow() < as_aware(theme.ends_at):
        return []
    likes = like_counts_subquery()
    q = (eligible_entries(theme.id).add_columns(func.coalesce(likes.c.n, 0).label("likes"))
         .outerjoin(likes, likes.c.photo_id == ThemeEntry.photo_id)
         .order_by(func.coalesce(likes.c.n, 0).desc(), ThemeEntry.created_at.asc()).limit(1))
    top = (await db.execute(q)).first()
    theme.finalized_at = utcnow()
    created = []
    if top and top.likes >= 1:
        entry = top[0]
        theme.winner_entry_id = entry.id
        n = await notify(db, user_id=entry.user_id, type="theme_won", photo_id=entry.photo_id,
                         data={"theme_id": str(theme.id), "number": theme.number,
                               "theme_tr": theme.title_tr, "theme_en": theme.title_en})
        if n:
            created.append(n)
    return created
