import json
import uuid

from fastapi import APIRouter, Depends, Header, Request
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.core.config import get_settings
from app.core.database import get_db
from app.core.errors import AppError
from app.core.security import as_aware, utcnow
from app.models import StripeCustomer, Subscription, User
from app.schemas import BillingStatus, CheckoutIn
from app.services import billing

router = APIRouter(prefix="/billing", tags=["billing"])


async def _status(db: AsyncSession, user: User) -> BillingStatus:
    await billing.recompute_pro(db, user.id)
    await db.commit()
    s = get_settings()
    subs = list(await db.scalars(select(Subscription).where(Subscription.user_id == user.id)))
    now = utcnow()
    current = max((x for x in subs if x.status in billing.VALID and (x.period_end is None or as_aware(x.period_end) > now)),
                  key=lambda x: as_aware(x.period_end) if x.period_end else now, default=None)
    return BillingStatus(
        is_pro=user.is_pro, store=current.store if current else None, status=current.status if current else None,
        period_end=current.period_end if current else None, will_renew=bool(current and current.will_renew),
        can_manage_on_web=bool(current and current.store == "stripe"),
        prices={"monthly": s.pro_price_monthly_display, "yearly": s.pro_price_yearly_display},
    )


@router.get("/status", response_model=BillingStatus)
async def status(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    return await _status(db, user)


@router.post("/sync", response_model=BillingStatus)
async def sync(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    """Mobil satın alma sonrası çağrılır: webhook gecikse bile Pro hemen açılır."""
    await billing.sync_revenuecat(db, user.id)
    return await _status(db, user)


@router.post("/checkout")
async def checkout(body: CheckoutIn, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    s = get_settings()
    price = s.stripe_price_monthly if body.plan == "monthly" else s.stripe_price_yearly
    if not s.stripe_secret_key or not price:
        raise AppError(503, "billing_not_configured")
    if user.is_pro:
        raise AppError(409, "already_pro")
    data = {
        "mode": "subscription", "line_items[0][price]": price, "line_items[0][quantity]": "1",
        "client_reference_id": str(user.id), "subscription_data[metadata][user_id]": str(user.id),
        "success_url": f"{s.frontend_url}/{user.locale}/pro?status=success",
        "cancel_url": f"{s.frontend_url}/{user.locale}/pro", "allow_promotion_codes": "true", "locale": user.locale,
    }
    existing = await db.get(StripeCustomer, user.id)
    if existing:
        data["customer"] = existing.customer_id
    else:
        data["customer_email"] = user.email
    session = await billing.stripe_request("POST", "checkout/sessions", data)
    return {"url": session["url"]}


@router.post("/portal")
async def portal(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    s = get_settings()
    customer = await db.get(StripeCustomer, user.id)
    if not s.stripe_secret_key:
        raise AppError(503, "billing_not_configured")
    if not customer:
        raise AppError(404, "no_web_subscription")
    session = await billing.stripe_request("POST", "billing_portal/sessions",
                                           {"customer": customer.customer_id, "return_url": f"{s.frontend_url}/{user.locale}/pro"})
    return {"url": session["url"]}


@router.post("/webhooks/stripe")
async def stripe_webhook(request: Request, stripe_signature: str = Header(default=""), db: AsyncSession = Depends(get_db)):
    s = get_settings()
    payload = await request.body()
    if not s.stripe_webhook_secret or not billing.verify_stripe_signature(payload, stripe_signature, s.stripe_webhook_secret):
        raise AppError(400, "invalid_signature")
    event = json.loads(payload)
    if await billing.already_processed(db, f"stripe:{event['id']}"):
        return {"ok": True, "duplicate": True}
    user_id = await billing.apply_stripe_event(db, event)
    if user_id:
        await billing.recompute_pro(db, user_id)
    await db.commit()
    return {"ok": True}


@router.post("/webhooks/revenuecat")
async def revenuecat_webhook(request: Request, authorization: str = Header(default=""), db: AsyncSession = Depends(get_db)):
    s = get_settings()
    if not s.revenuecat_webhook_auth or authorization != s.revenuecat_webhook_auth:
        raise AppError(401, "invalid_signature")
    event = (await request.json()).get("event", {})
    if event.get("id") and await billing.already_processed(db, f"rc:{event['id']}"):
        return {"ok": True, "duplicate": True}
    user_id = await billing.apply_revenuecat_event(db, event)
    if user_id:
        await billing.recompute_pro(db, user_id)
    await db.commit()
    return {"ok": True}
