"""Pro yetkisi: mağaza kayıtlarından türetilir, webhook'larla güncellenir."""
import hashlib
import hmac
import json
import logging
import time
import uuid
from datetime import datetime, timezone

import httpx
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.security import as_aware, utcnow
from app.models import ProcessedWebhook, StripeCustomer, Subscription, User

log = logging.getLogger("photomunity.billing")
VALID = {"active", "grace", "cancelled"}  # cancelled: yenilenmeyecek ama dönem sonuna kadar geçerli


def _valid(sub: Subscription, now: datetime) -> bool:
    if sub.status not in VALID:
        return False
    return sub.period_end is None or as_aware(sub.period_end) > now


async def recompute_pro(db: AsyncSession, user_id: uuid.UUID) -> bool:
    """Kullanıcının tüm aboneliklerinden Pro durumunu hesaplar ve users.is_pro'ya yazar."""
    now = utcnow()
    subs = list(await db.scalars(select(Subscription).where(Subscription.user_id == user_id)))
    for s in subs:
        if s.status in VALID and s.period_end is not None and as_aware(s.period_end) <= now:
            s.status = "expired"
    user = await db.get(User, user_id)
    if user is not None:
        user.is_pro = any(_valid(s, now) for s in subs)
    return bool(user and user.is_pro)


async def already_processed(db: AsyncSession, event_id: str) -> bool:
    if await db.get(ProcessedWebhook, event_id):
        return True
    db.add(ProcessedWebhook(event_id=event_id))
    return False


async def upsert(db: AsyncSession, *, user_id: uuid.UUID, store: str, external_id: str, product_id: str | None,
                 status: str, period_end: datetime | None, will_renew: bool) -> Subscription:
    sub = await db.scalar(select(Subscription).where(Subscription.external_id == external_id))
    if sub is None:
        sub = Subscription(user_id=user_id, store=store, external_id=external_id)
        db.add(sub)
    sub.user_id, sub.store, sub.product_id, sub.status, sub.period_end, sub.will_renew = user_id, store, product_id, status, period_end, will_renew
    return sub


def _ms(v) -> datetime | None:
    return datetime.fromtimestamp(v / 1000, tz=timezone.utc) if v else None


# ---------------------------------------------------------------- RevenueCat (App Store / Google Play)

RC_STATUS = {
    "INITIAL_PURCHASE": ("active", True), "RENEWAL": ("active", True), "PRODUCT_CHANGE": ("active", True),
    "UNCANCELLATION": ("active", True), "NON_RENEWING_PURCHASE": ("active", False),
    "CANCELLATION": ("cancelled", False),  # dönem sonuna kadar Pro kalır
    "BILLING_ISSUE": ("grace", True),       # mağazanın ödeme tekrar deneme süresi
    "SUBSCRIPTION_PAUSED": ("expired", False), "EXPIRATION": ("expired", False),
}


def _rc_store(store: str | None) -> str:
    return {"APP_STORE": "app_store", "MAC_APP_STORE": "app_store", "PLAY_STORE": "play_store"}.get(store or "", (store or "other").lower()[:16])


async def apply_revenuecat_event(db: AsyncSession, event: dict) -> uuid.UUID | None:
    etype = event.get("type")
    if etype == "TEST" or etype not in RC_STATUS:
        return None
    try:
        user_id = uuid.UUID(str(event.get("app_user_id")))
    except ValueError:
        log.warning("RevenueCat: tanınmayan app_user_id %s", event.get("app_user_id"))
        return None
    if not await db.get(User, user_id):
        return None
    status, will_renew = RC_STATUS[etype]
    await upsert(db, user_id=user_id, store=_rc_store(event.get("store")),
                 external_id=f"rc:{user_id}",  # RevenueCat kullanıcının mağaza durumunu zaten birleştirir: kullanıcı başına tek kayıt
                 product_id=event.get("product_id"), status=status, period_end=_ms(event.get("expiration_at_ms")), will_renew=will_renew)
    return user_id


async def sync_revenuecat(db: AsyncSession, user_id: uuid.UUID) -> None:
    """Satın alma sonrası webhook'u beklemeden RevenueCat'ten güncel durumu çeker."""
    s = get_settings()
    if not s.revenuecat_secret_key:
        return
    async with httpx.AsyncClient(timeout=10) as client:
        r = await client.get(f"https://api.revenuecat.com/v1/subscribers/{user_id}", headers={"Authorization": f"Bearer {s.revenuecat_secret_key}"})
    if r.status_code != 200:
        log.warning("RevenueCat senkronu başarısız: %s", r.status_code)
        return
    sub = r.json().get("subscriber", {})
    ent = sub.get("entitlements", {}).get(s.revenuecat_entitlement)
    if not ent:
        return
    product = ent.get("product_identifier")
    info = sub.get("subscriptions", {}).get(product, {})
    exp = ent.get("expires_date")
    period_end = datetime.fromisoformat(exp.replace("Z", "+00:00")) if exp else None
    cancelled = bool(info.get("unsubscribe_detected_at"))
    status = "grace" if info.get("billing_issues_detected_at") else ("cancelled" if cancelled else "active")
    await upsert(db, user_id=user_id, store=_rc_store(info.get("store")), external_id=f"rc:{user_id}",
                 product_id=product, status=status, period_end=period_end, will_renew=not cancelled)


# ---------------------------------------------------------------- Stripe (web)

def verify_stripe_signature(payload: bytes, header: str, secret: str, tolerance: int = 300) -> bool:
    """Stripe-Signature: t=<zaman>,v1=<HMAC-SHA256(t.payload)>; tekrar oynatmaya karşı zaman toleransı."""
    try:
        parts = dict(p.split("=", 1) for p in header.split(","))
        ts = int(parts["t"])
    except (ValueError, KeyError):
        return False
    if abs(time.time() - ts) > tolerance:
        return False
    expected = hmac.new(secret.encode(), f"{ts}.".encode() + payload, hashlib.sha256).hexdigest()
    signatures = [v for k, v in (p.split("=", 1) for p in header.split(",")) if k == "v1"]
    return any(hmac.compare_digest(expected, sig) for sig in signatures)


STRIPE_STATUS = {"active": "active", "trialing": "active", "past_due": "grace", "canceled": "expired",
                 "unpaid": "expired", "incomplete_expired": "expired", "incomplete": "expired", "paused": "expired"}


async def stripe_request(method: str, path: str, data: dict | None = None) -> dict:
    """Stripe REST API (form kodlamalı). Testlerde bu fonksiyon değiştirilir."""
    s = get_settings()
    async with httpx.AsyncClient(timeout=15) as client:
        r = await client.request(method, f"https://api.stripe.com/v1/{path}", data=data, auth=(s.stripe_secret_key, ""))
    r.raise_for_status()
    return r.json()


async def apply_stripe_event(db: AsyncSession, event: dict) -> uuid.UUID | None:
    etype, obj = event.get("type", ""), event.get("data", {}).get("object", {})
    if etype == "checkout.session.completed":
        user_id = uuid.UUID(obj["client_reference_id"])
        if obj.get("customer") and not await db.get(StripeCustomer, user_id):
            db.add(StripeCustomer(user_id=user_id, customer_id=obj["customer"]))
        if obj.get("subscription"):
            sub = await stripe_request("GET", f"subscriptions/{obj['subscription']}")
            await _apply_stripe_subscription(db, user_id, sub)
        return user_id
    if etype.startswith("customer.subscription."):
        customer = await db.scalar(select(StripeCustomer).where(StripeCustomer.customer_id == obj.get("customer")))
        user_id = customer.user_id if customer else _meta_user(obj)
        if user_id is None:
            return None
        await _apply_stripe_subscription(db, user_id, obj, deleted=etype.endswith("deleted"))
        return user_id
    return None


def _meta_user(obj: dict) -> uuid.UUID | None:
    try:
        return uuid.UUID(obj.get("metadata", {}).get("user_id", ""))
    except ValueError:
        return None


async def _apply_stripe_subscription(db: AsyncSession, user_id: uuid.UUID, sub: dict, deleted: bool = False) -> None:
    status = "expired" if deleted else STRIPE_STATUS.get(sub.get("status", ""), "expired")
    if status == "active" and sub.get("cancel_at_period_end"):
        status = "cancelled"
    end = sub.get("current_period_end") or (sub.get("items", {}).get("data") or [{}])[0].get("current_period_end")
    price = ((sub.get("items", {}).get("data") or [{}])[0].get("price") or {}).get("id")
    await upsert(db, user_id=user_id, store="stripe", external_id=sub["id"], product_id=price, status=status,
                 period_end=datetime.fromtimestamp(end, tz=timezone.utc) if end else None,
                 will_renew=not sub.get("cancel_at_period_end") and status == "active")
