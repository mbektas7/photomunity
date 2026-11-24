"""Çekim planı hatırlatmaları ve hava (bulut) uyarısı. Worker bu fonksiyonları zamanlanmış olarak çağırır."""
import logging
from datetime import datetime, timedelta

import httpx
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.security import as_aware
from app.models import Notification, PlanJoin, ShootPlan
from app.services import themes as tsvc
from app.services.notifications import notify

log = logging.getLogger("photomunity.plans")

KIND_LABELS = {
    "milkyway": ("Samanyolu", "Milky Way"),
    "golden": ("Altın saat", "golden hour"),
    "blue": ("Mavi saat", "blue hour"),
    "moonrise": ("Ay doğuşu", "moonrise"),
    "meteor": ("Meteor", "meteor"),
    "other": ("Çekim", "photo"),
}
DAY, HOUR2 = timedelta(hours=24), timedelta(hours=2)


def utcnow() -> datetime:
    return tsvc.utcnow()


def _preset_flags(target: datetime, now: datetime) -> tuple[datetime | None, datetime | None]:
    left = as_aware(target) - now
    return (now if left <= DAY else None), (now if left <= HOUR2 else None)


def preset_reminders(plan: ShootPlan, now: datetime | None = None) -> None:
    """Plan hedefe 24 saatten (2 saatten) az kala kaydedildiyse o hatırlatma zaten gereksiz: gönderilmiş say."""
    now = now or utcnow()
    plan.reminded_day_at, plan.reminded_hour_at = _preset_flags(plan.target_at, now)
    plan.weather_alerted_at = None


def preset_join_reminders(join: PlanJoin, plan: ShootPlan, now: datetime | None = None) -> None:
    """Katılım için aynı kural: hedefe 24 saatten (2 saatten) az kala katılan o hatırlatmayı almaz."""
    join.reminded_day_at, join.reminded_hour_at = _preset_flags(plan.target_at, now or utcnow())


async def reset_join_reminders(db: AsyncSession, plan: ShootPlan, now: datetime | None = None) -> None:
    """Plan zamanı değişince katılımcıların hatırlatma bayrakları yeni hedefe göre sıfırlanır."""
    day, hour = _preset_flags(plan.target_at, now or utcnow())
    await db.execute(update(PlanJoin).where(PlanJoin.plan_id == plan.id)
                     .values(reminded_day_at=day, reminded_hour_at=hour))


def _next_reminder(obj, left: timedelta, now: datetime) -> int | None:
    """obj (ShootPlan ya da PlanJoin) için sıradaki hatırlatma (24 | 2) ve bayrak güncellemesi."""
    if obj.reminded_hour_at is None and left <= HOUR2:
        obj.reminded_hour_at = now
        obj.reminded_day_at = obj.reminded_day_at or now
        return 2
    if obj.reminded_day_at is None:
        obj.reminded_day_at = now
        return 24
    return None


def _labels(p: ShootPlan) -> dict:
    tr, en = KIND_LABELS.get(p.kind, KIND_LABELS["other"])
    return {"plan_tr": p.title or tr, "plan_en": p.title or en}


def _data(p: ShootPlan, **extra) -> dict:
    return {"plan_id": str(p.id), "kind": p.kind, "place": p.place_name or "",
            "target_at": as_aware(p.target_at).isoformat(), **_labels(p), **extra}


async def send_plan_reminders(db: AsyncSession) -> list[Notification]:
    """~24 saat ve ~2 saat önce "plan_reminder" (data.hours = 24 | 2), sahibine ve katılımcılara. Her biri bir kez.
    Commit çağırana aittir."""
    now = utcnow()
    created: list[Notification] = []
    rows = await db.scalars(select(ShootPlan).where(
        ShootPlan.remind.is_(True), ShootPlan.target_at > now, ShootPlan.target_at <= now + DAY,
        (ShootPlan.reminded_day_at.is_(None)) | (ShootPlan.reminded_hour_at.is_(None))))
    for p in rows:
        hours = _next_reminder(p, as_aware(p.target_at) - now, now)
        if hours:
            n = await notify(db, user_id=p.user_id, type="plan_reminder", data=_data(p, hours=hours))
            if n:
                created.append(n)
    # Paylaşılan planlara katılanlar: aynı metin ve veri, kendi bayraklarıyla (sahibin remind ayarından bağımsız)
    joins = (await db.execute(select(PlanJoin, ShootPlan).join(ShootPlan, ShootPlan.id == PlanJoin.plan_id).where(
        ShootPlan.shared.is_(True), ShootPlan.target_at > now, ShootPlan.target_at <= now + DAY,
        (PlanJoin.reminded_day_at.is_(None)) | (PlanJoin.reminded_hour_at.is_(None))))).all()
    for j, p in joins:
        hours = _next_reminder(j, as_aware(p.target_at) - now, now)
        if hours:
            n = await notify(db, user_id=j.user_id, type="plan_reminder", data=_data(p, hours=hours))
            if n:
                created.append(n)
    return created


async def fetch_cloud_cover(lat: float, lng: float, target: datetime) -> int | None:
    """Open-Meteo saatlik tahmininden hedef saatin bulut oranı (%). Ağ/biçim hatasında None (loglanır)."""
    s = get_settings()
    params = {"latitude": round(lat, 3), "longitude": round(lng, 3), "hourly": "cloud_cover", "timezone": "UTC",
              "forecast_days": 3}
    try:
        async with httpx.AsyncClient(timeout=s.weather_timeout_seconds) as client:
            r = await client.get(s.open_meteo_url, params=params)
            r.raise_for_status()
            hourly = r.json()["hourly"]
        key = as_aware(target).strftime("%Y-%m-%dT%H:00")
        values = dict(zip(hourly["time"], hourly["cloud_cover"]))
        v = values.get(key)
        return int(round(v)) if v is not None else None
    except Exception as exc:  # noqa: BLE001 — hava servisi hatası planları etkilememeli
        log.warning("Open-Meteo okunamadı (%s, %s): %s", lat, lng, exc)
        return None


async def check_plan_weather(db: AsyncSession) -> list[Notification]:
    """Önümüzdeki 48 saatteki, uyarısı açık planlar için bulut kontrolü; eşik aşılırsa bir kez "plan_weather"."""
    now = utcnow()
    threshold = get_settings().weather_cloud_alert_percent
    created: list[Notification] = []
    rows = list(await db.scalars(select(ShootPlan).where(
        ShootPlan.weather_alert.is_(True), ShootPlan.weather_alerted_at.is_(None),
        ShootPlan.target_at > now, ShootPlan.target_at <= now + timedelta(hours=48)).limit(2000)))
    cache: dict[tuple, int | None] = {}
    for p in rows:
        key = (round(p.latitude, 2), round(p.longitude, 2), as_aware(p.target_at).strftime("%Y%m%d%H"))
        if key not in cache:
            cache[key] = await fetch_cloud_cover(p.latitude, p.longitude, p.target_at)
        cloud = cache[key]
        if cloud is None:
            continue
        p.last_cloud_cover, p.weather_checked_at = cloud, now
        if cloud > threshold:
            p.weather_alerted_at = now
            n = await notify(db, user_id=p.user_id, type="plan_weather", data=_data(p, cloud=cloud))
            if n:
                created.append(n)
    return created
