"""Çekim planı hatırlatmaları ve hava (bulut) uyarısı. Worker bu fonksiyonları zamanlanmış olarak çağırır."""
import logging
from datetime import datetime, timedelta

import httpx
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.security import as_aware
from app.models import Notification, ShootPlan
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


def preset_reminders(plan: ShootPlan, now: datetime | None = None) -> None:
    """Plan hedefe 24 saatten (2 saatten) az kala kaydedildiyse o hatırlatma zaten gereksiz: gönderilmiş say."""
    now = now or utcnow()
    left = as_aware(plan.target_at) - now
    plan.reminded_day_at = now if left <= DAY else None
    plan.reminded_hour_at = now if left <= HOUR2 else None
    plan.weather_alerted_at = None


def _labels(p: ShootPlan) -> dict:
    tr, en = KIND_LABELS.get(p.kind, KIND_LABELS["other"])
    return {"plan_tr": p.title or tr, "plan_en": p.title or en}


def _data(p: ShootPlan, **extra) -> dict:
    return {"plan_id": str(p.id), "kind": p.kind, "place": p.place_name or "",
            "target_at": as_aware(p.target_at).isoformat(), **_labels(p), **extra}


async def send_plan_reminders(db: AsyncSession) -> list[Notification]:
    """~24 saat ve ~2 saat önce "plan_reminder" (data.hours = 24 | 2). Her biri bir kez. Commit çağırana aittir."""
    now = utcnow()
    created: list[Notification] = []
    rows = await db.scalars(select(ShootPlan).where(
        ShootPlan.remind.is_(True), ShootPlan.target_at > now, ShootPlan.target_at <= now + DAY,
        (ShootPlan.reminded_day_at.is_(None)) | (ShootPlan.reminded_hour_at.is_(None))))
    for p in rows:
        left = as_aware(p.target_at) - now
        hours = None
        if p.reminded_hour_at is None and left <= HOUR2:
            p.reminded_hour_at = now
            p.reminded_day_at = p.reminded_day_at or now
            hours = 2
        elif p.reminded_day_at is None:
            p.reminded_day_at = now
            hours = 24
        if hours:
            n = await notify(db, user_id=p.user_id, type="plan_reminder", data=_data(p, hours=hours))
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
