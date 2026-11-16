"""Halk oylaması: e-posta normalizasyonu, geçici adres engeli, tek kullanımlık kod, bot doğrulaması."""
import hashlib
import secrets
import uuid
from datetime import datetime

import httpx
import jwt

from app.core.config import get_settings

GMAIL = {"gmail.com", "googlemail.com"}

# Sık kullanılan geçici e-posta servisleri. Üretimde düzenli güncellenen bir liste (ör. disposable-email-domains) kullanılmalı.
DISPOSABLE_DOMAINS = {
    "mailinator.com", "10minutemail.com", "guerrillamail.com", "guerrillamail.net", "sharklasers.com", "tempmail.com",
    "temp-mail.org", "tempmail.plus", "yopmail.com", "trashmail.com", "getnada.com", "maildrop.cc", "dispostable.com",
    "throwawaymail.com", "fakeinbox.com", "mintemail.com", "emailondeck.com", "mohmal.com", "minuteinbox.com",
    "burnermail.io", "moakt.com", "spamgourmet.com", "mailnesia.com", "tempr.email", "discard.email",
}


def normalize_email(email: str) -> str:
    """Aynı kutuya giden varyasyonları tek anahtara indirger: büyük/küçük harf, +etiket, Gmail noktaları."""
    local, _, domain = email.strip().lower().partition("@")
    local = local.split("+", 1)[0]
    if domain in GMAIL:
        local, domain = local.replace(".", ""), "gmail.com"
    return f"{local}@{domain}"


def is_disposable(email: str) -> bool:
    domain = email.rsplit("@", 1)[-1].lower()
    return domain in DISPOSABLE_DOMAINS or any(domain.endswith("." + d) for d in DISPOSABLE_DOMAINS)


def new_code() -> str:
    return f"{secrets.randbelow(1_000_000):06d}"


def hash_code(contest_id: uuid.UUID, email: str, code: str) -> str:
    return hashlib.sha256(f"{contest_id}:{email}:{code}:{get_settings().jwt_secret}".encode()).hexdigest()


def hash_ip(ip: str) -> str:
    return hashlib.sha256(f"{ip}:{get_settings().jwt_secret}".encode()).hexdigest()[:32]


def voter_token(voter_id: uuid.UUID, contest_id: uuid.UUID, expires: datetime) -> str:
    s = get_settings()
    return jwt.encode({"type": "voter", "sub": str(voter_id), "cid": str(contest_id), "exp": expires},
                      s.jwt_secret, algorithm=s.jwt_algorithm)


def read_voter_token(token: str, contest_id: uuid.UUID) -> uuid.UUID | None:
    s = get_settings()
    try:
        payload = jwt.decode(token, s.jwt_secret, algorithms=[s.jwt_algorithm])
    except jwt.PyJWTError:
        return None
    if payload.get("type") != "voter" or payload.get("cid") != str(contest_id):
        return None
    return uuid.UUID(payload["sub"])


async def verify_turnstile(token: str | None, ip: str) -> bool:
    secret = get_settings().turnstile_secret
    if not secret:
        return True
    if not token:
        return False
    try:
        async with httpx.AsyncClient(timeout=8) as client:
            r = await client.post("https://challenges.cloudflare.com/turnstile/v0/siteverify",
                                  data={"secret": secret, "response": token, "remoteip": ip})
            return bool(r.json().get("success"))
    except httpx.HTTPError:
        return False
