import hashlib
import hmac
import json
import time
import uuid
from datetime import datetime, timedelta, timezone

import pytest

import app.services.billing as billing
import app.worker as worker
from app.core.config import get_settings
from tests.test_api import register

pytestmark = pytest.mark.asyncio
RC_AUTH = "Bearer rc-webhook-secret"
WH_SECRET = "whsec_test"


@pytest.fixture(autouse=True)
def configure(monkeypatch):
    s = get_settings()
    for k, v in {"revenuecat_webhook_auth": RC_AUTH, "stripe_webhook_secret": WH_SECRET, "stripe_secret_key": "sk_test",
                 "stripe_price_monthly": "price_month", "stripe_price_yearly": "price_year"}.items():
        monkeypatch.setattr(s, k, v)


def ms(dt):
    return int(dt.timestamp() * 1000)


async def rc(client, user_id, etype, expires, eid=None):
    return await client.post("/billing/webhooks/revenuecat", headers={"Authorization": RC_AUTH}, json={"event": {
        "id": eid or str(uuid.uuid4()), "type": etype, "app_user_id": user_id, "store": "APP_STORE",
        "product_id": "photomunity_pro_monthly", "original_transaction_id": "1000000123", "expiration_at_ms": ms(expires)}})


async def status(client, h):
    return (await client.get("/billing/status", headers=h)).json()


async def test_revenuecat_lifecycle(client):
    h, body = await register(client, "abone")
    uid = body["user"]["id"]
    s = await status(client, h)
    assert s["is_pro"] is False and s["prices"] == {"monthly": "$1.99", "yearly": "$17.99"}

    bad = await client.post("/billing/webhooks/revenuecat", headers={"Authorization": "Bearer yanlis"}, json={"event": {}})
    assert bad.status_code == 401

    future = datetime.now(timezone.utc) + timedelta(days=30)
    await rc(client, uid, "INITIAL_PURCHASE", future, eid="evt-1")
    s = await status(client, h)
    assert s["is_pro"] and s["store"] == "app_store" and s["will_renew"] and s["can_manage_on_web"] is False
    assert (await client.get("/me", headers=h)).json()["is_pro"] is True
    dup = await rc(client, uid, "EXPIRATION", future, eid="evt-1")  # aynı olay kimliği tekrar gelirse yok sayılır
    assert dup.json()["duplicate"] and (await status(client, h))["is_pro"]

    await rc(client, uid, "CANCELLATION", future)  # iptal: dönem sonuna kadar Pro
    s = await status(client, h)
    assert s["is_pro"] and s["status"] == "cancelled" and s["will_renew"] is False

    await rc(client, uid, "BILLING_ISSUE", future)  # ödeme sorunu: mağaza tekrar denerken Pro kalır
    assert (await status(client, h))["status"] == "grace"

    await rc(client, uid, "EXPIRATION", datetime.now(timezone.utc) - timedelta(minutes=1))
    assert (await status(client, h))["is_pro"] is False

    unknown = await rc(client, str(uuid.uuid4()), "INITIAL_PURCHASE", future)
    assert unknown.status_code == 200  # tanınmayan kullanıcı: kabul et ama işlem yapma


def stripe_sig(payload: bytes, secret=WH_SECRET, ts=None):
    ts = ts or int(time.time())
    sig = hmac.new(secret.encode(), f"{ts}.".encode() + payload, hashlib.sha256).hexdigest()
    return f"t={ts},v1={sig}"


async def stripe_event(client, event, sig=None):
    payload = json.dumps(event).encode()
    return await client.post("/billing/webhooks/stripe", content=payload,
                             headers={"Stripe-Signature": sig or stripe_sig(payload), "content-type": "application/json"})


async def test_stripe_checkout_webhooks_and_portal(client, monkeypatch):
    h, body = await register(client, "webabone")
    uid = body["user"]["id"]
    end = int((datetime.now(timezone.utc) + timedelta(days=30)).timestamp())
    calls = []

    async def fake_stripe(method, path, data=None):
        calls.append((method, path, data))
        if path == "checkout/sessions":
            return {"url": "https://checkout.stripe.com/c/pay/cs_test_1"}
        if path.startswith("subscriptions/"):
            return {"id": "sub_1", "status": "active", "cancel_at_period_end": False, "current_period_end": end,
                    "items": {"data": [{"price": {"id": "price_month"}}]}}
        if path == "billing_portal/sessions":
            return {"url": "https://billing.stripe.com/p/session_1"}
        raise AssertionError(path)

    monkeypatch.setattr(billing, "stripe_request", fake_stripe)

    r = await client.post("/billing/checkout", headers=h, json={"plan": "yearly"})
    assert r.json()["url"].startswith("https://checkout.stripe.com")
    sent = calls[-1][2]
    assert sent["line_items[0][price]"] == "price_year" and sent["client_reference_id"] == uid and sent["customer_email"] == "webabone@example.com"
    assert (await client.post("/billing/portal", headers=h)).json()["error"]["code"] == "no_web_subscription"

    # İmza: yanlış sır, bozuk başlık ve eski zaman damgası reddedilir
    ev = {"id": "evt_s1", "type": "checkout.session.completed",
          "data": {"object": {"client_reference_id": uid, "customer": "cus_1", "subscription": "sub_1"}}}
    payload = json.dumps(ev).encode()
    assert (await stripe_event(client, ev, sig=stripe_sig(payload, secret="baska"))).status_code == 400
    assert (await stripe_event(client, ev, sig="bozuk")).status_code == 400
    assert (await stripe_event(client, ev, sig=stripe_sig(payload, ts=int(time.time()) - 3600))).status_code == 400

    assert (await stripe_event(client, ev)).status_code == 200
    s = await status(client, h)
    assert s["is_pro"] and s["store"] == "stripe" and s["can_manage_on_web"]
    assert (await client.post("/billing/checkout", headers=h, json={"plan": "monthly"})).json()["error"]["code"] == "already_pro"
    assert (await client.post("/billing/portal", headers=h)).json()["url"].startswith("https://billing.stripe.com")

    # Dönem sonunda iptal: Pro kalır ama yenilenmez; silinince Pro biter
    upd = {"id": "evt_s2", "type": "customer.subscription.updated", "data": {"object": {
        "id": "sub_1", "customer": "cus_1", "status": "active", "cancel_at_period_end": True, "current_period_end": end,
        "items": {"data": [{"price": {"id": "price_month"}}]}}}}
    await stripe_event(client, upd)
    s = await status(client, h)
    assert s["is_pro"] and s["status"] == "cancelled" and not s["will_renew"]
    deleted = {"id": "evt_s3", "type": "customer.subscription.deleted", "data": {"object": {**upd["data"]["object"], "status": "canceled"}}}
    await stripe_event(client, deleted)
    assert (await status(client, h))["is_pro"] is False


async def test_subscription_tick_expires_stale(client, monkeypatch):
    h, body = await register(client, "suresi")
    soon = datetime.now(timezone.utc) + timedelta(hours=1)
    await rc(client, body["user"]["id"], "RENEWAL", soon)
    assert (await client.get("/me", headers=h)).json()["is_pro"]
    # Webhook hiç gelmeden dönem bitti: saatlik görev Pro'yu kapatır
    monkeypatch.setattr(worker, "utcnow", lambda: soon + timedelta(minutes=5))
    monkeypatch.setattr(billing, "utcnow", lambda: soon + timedelta(minutes=5))
    await worker.subscription_tick({})
    assert (await client.get("/me", headers=h)).json()["is_pro"] is False


async def test_pro_gets_higher_upload_limit(client, monkeypatch):
    from app.services.ratelimit import limiter

    monkeypatch.setattr(get_settings(), "rate_limit_enabled", True)
    limiter.reset()
    h, body = await register(client, "yukleyici")
    body_ = {"content_type": "image/jpeg", "size_bytes": 2_000_000}
    codes = [(await client.post("/photos/upload-url", headers=h, json=body_)).status_code for _ in range(61)]
    assert codes[-1] == 429
    await rc(client, body["user"]["id"], "INITIAL_PURCHASE", datetime.now(timezone.utc) + timedelta(days=30))
    assert (await client.post("/photos/upload-url", headers=h, json=body_)).status_code == 201  # Pro: 200/saat
    limiter.reset()


async def test_public_stats(client, fake_storage):
    import app.api.v1.stats as stats
    from tests.test_phase1_complete import upload_photo

    stats._cache.update(at=0.0, data=None)
    h, _ = await register(client, "sayac")
    await client.patch("/me", headers=h, json={"country": "TR"})
    await upload_photo(client, h, fake_storage)
    s = (await client.get("/stats/public")).json()
    assert s == {"photographers": 1, "photos": 1, "communities": 0, "countries": 1, "open_contests": 0}
