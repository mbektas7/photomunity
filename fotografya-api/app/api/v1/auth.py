import re
import secrets
import uuid
from datetime import timedelta
from typing import Literal

import jwt
from fastapi import APIRouter, BackgroundTasks, Depends, Response
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession
from starlette.concurrency import run_in_threadpool

from app.api.deps import get_current_user
from app.core.config import get_settings
from app.core.database import get_db
from app.core.errors import AppError
from app.core.security import (
    as_aware, create_access_token, create_refresh_token, decode_token, hash_password, hash_token,
    new_opaque_token, utcnow, verify_password,
)
from app.models import AuthIdentity, AuthProvider, OneTimeToken, Photo, RefreshSession, TokenPurpose, User
from app.schemas import (
    AuthResponse, ChangePasswordIn, EmailIn, LoginIn, MeOut, OAuthIn, RefreshIn, RegisterIn, ResetPasswordIn,
    TokenIn, TokenPair,
)
from app.services import storage
from app.services.email import send_template
from app.services.oauth import OAuthError, verify_id_token
from app.services.ratelimit import rate_limit

router = APIRouter(prefix="/auth", tags=["auth"])


async def issue_tokens(db: AsyncSession, user: User) -> TokenPair:
    s = get_settings()
    session = RefreshSession(id=uuid.uuid4(), user_id=user.id, expires_at=utcnow() + timedelta(days=s.refresh_token_days))
    db.add(session)
    return TokenPair(
        access_token=create_access_token(user.id),
        refresh_token=create_refresh_token(user.id, session.id),
        expires_in=s.access_token_minutes * 60,
    )


async def _one_time_link(db: AsyncSession, user: User, purpose: TokenPurpose, hours: int, path: str) -> str:
    token = new_opaque_token()
    db.add(OneTimeToken(user_id=user.id, purpose=purpose, token_hash=hash_token(token),
                        expires_at=utcnow() + timedelta(hours=hours)))
    return f"{get_settings().frontend_url}/{path}?token={token}"


async def _consume(db: AsyncSession, token: str, purpose: TokenPurpose) -> User:
    row = await db.scalar(select(OneTimeToken).where(OneTimeToken.token_hash == hash_token(token),
                                                     OneTimeToken.purpose == purpose))
    if not row or row.used_at or as_aware(row.expires_at) < utcnow():
        raise AppError(400, "invalid_link")
    row.used_at = utcnow()
    user = await db.get(User, row.user_id)
    if not user:
        raise AppError(400, "invalid_link")
    return user


async def _revoke_all(db: AsyncSession, user_id: uuid.UUID) -> None:
    await db.execute(update(RefreshSession).where(RefreshSession.user_id == user_id).values(revoked=True))


async def _unique_username(db: AsyncSession, seed: str) -> str:
    base = re.sub(r"[^a-z0-9_.]", "", seed.lower().replace(" ", "."))[:20].strip(".") or "foto"
    base = base if len(base) >= 3 else f"{base}foto"
    candidate = base
    while await db.scalar(select(User.id).where(User.username == candidate)):
        candidate = f"{base}{secrets.randbelow(9000) + 1000}"
    return candidate


@router.post("/register", response_model=AuthResponse, status_code=201, dependencies=[rate_limit("register", 10, 3600)])
async def register(body: RegisterIn, background: BackgroundTasks, db: AsyncSession = Depends(get_db)):
    email = body.email.lower()
    if await db.scalar(select(User.id).where(User.email == email)):
        raise AppError(409, "email_taken")
    if await db.scalar(select(User.id).where(User.username == body.username)):
        raise AppError(409, "username_taken")

    user = User(id=uuid.uuid4(), email=email, username=body.username, display_name=body.display_name,
                locale=body.locale, specialties=[])
    db.add(user)
    await db.flush()
    db.add(AuthIdentity(user_id=user.id, provider=AuthProvider.email, provider_uid=email,
                        password_hash=hash_password(body.password)))
    link = await _one_time_link(db, user, TokenPurpose.verify_email, 48, "verify-email")
    tokens = await issue_tokens(db, user)
    await db.commit()
    await db.refresh(user)
    background.add_task(send_template, user.email, "verify_email", user.locale, link)
    return AuthResponse(user=MeOut.model_validate(user), tokens=tokens, is_new_user=True)


@router.post("/login", response_model=AuthResponse, dependencies=[rate_limit("login", 20, 900)])
async def login(body: LoginIn, db: AsyncSession = Depends(get_db)):
    email = body.email.lower()
    ident = await db.scalar(select(AuthIdentity).where(AuthIdentity.provider == AuthProvider.email,
                                                       AuthIdentity.provider_uid == email))
    if not ident or not verify_password(body.password, ident.password_hash):
        raise AppError(401, "invalid_credentials")
    user = await db.get(User, ident.user_id)
    if not user or not user.is_active:
        raise AppError(403, "account_disabled")
    tokens = await issue_tokens(db, user)
    await db.commit()
    return AuthResponse(user=MeOut.model_validate(user), tokens=tokens)


@router.post("/oauth/{provider}", response_model=AuthResponse, dependencies=[rate_limit("oauth", 30, 900)])
async def oauth_login(provider: Literal["google", "apple"], body: OAuthIn, db: AsyncSession = Depends(get_db)):
    try:
        profile = await run_in_threadpool(verify_id_token, provider, body.id_token)
    except OAuthError:
        raise AppError(401, "invalid_oauth_token")

    prov = AuthProvider(provider)
    ident = await db.scalar(select(AuthIdentity).where(AuthIdentity.provider == prov,
                                                       AuthIdentity.provider_uid == profile.sub))
    is_new = False
    if ident:
        user = await db.get(User, ident.user_id)
    else:
        if not profile.email:
            raise AppError(400, "email_required")
        email = profile.email.lower()
        user = await db.scalar(select(User).where(User.email == email))
        if user and not profile.email_verified:
            # Doğrulanmamış e-postayla mevcut hesaba bağlanmak hesap ele geçirmeye açık olur
            raise AppError(409, "email_taken")
        if not user:
            name = body.display_name or profile.name or email.split("@")[0]
            user = User(id=uuid.uuid4(), email=email, email_verified=profile.email_verified,
                        username=await _unique_username(db, body.username or name),
                        display_name=name[:80], locale=body.locale, specialties=[])
            db.add(user)
            await db.flush()
            is_new = True
        elif profile.email_verified:
            user.email_verified = True
        db.add(AuthIdentity(user_id=user.id, provider=prov, provider_uid=profile.sub))

    if not user or not user.is_active:
        raise AppError(403, "account_disabled")
    tokens = await issue_tokens(db, user)
    await db.commit()
    await db.refresh(user)
    return AuthResponse(user=MeOut.model_validate(user), tokens=tokens, is_new_user=is_new)


@router.post("/refresh", response_model=TokenPair)
async def refresh(body: RefreshIn, db: AsyncSession = Depends(get_db)):
    try:
        payload = decode_token(body.refresh_token, "refresh")
        session = await db.get(RefreshSession, uuid.UUID(payload["jti"]))
    except (jwt.PyJWTError, ValueError, KeyError):
        raise AppError(401, "invalid_token")
    if not session:
        raise AppError(401, "invalid_token")
    if session.revoked:
        # Kullanılmış bir refresh token tekrar geldi: çalınmış olabilir, tüm oturumları kapat
        await _revoke_all(db, session.user_id)
        await db.commit()
        raise AppError(401, "invalid_token")
    if as_aware(session.expires_at) < utcnow():
        raise AppError(401, "invalid_token")
    user = await db.get(User, session.user_id)
    if not user or not user.is_active:
        raise AppError(401, "invalid_token")
    session.revoked = True  # rotasyon
    tokens = await issue_tokens(db, user)
    await db.commit()
    return tokens


@router.post("/logout", status_code=204)
async def logout(body: RefreshIn, db: AsyncSession = Depends(get_db)):
    try:
        payload = decode_token(body.refresh_token, "refresh")
        session = await db.get(RefreshSession, uuid.UUID(payload["jti"]))
    except (jwt.PyJWTError, ValueError, KeyError):
        return Response(status_code=204)
    if session:
        session.revoked = True
        await db.commit()
    return Response(status_code=204)


@router.post("/verify-email", response_model=MeOut)
async def verify_email(body: TokenIn, db: AsyncSession = Depends(get_db)):
    user = await _consume(db, body.token, TokenPurpose.verify_email)
    user.email_verified = True
    await db.commit()
    return MeOut.model_validate(user)


@router.post("/resend-verification", status_code=202, dependencies=[rate_limit("resend", 5, 3600, by="user")])
async def resend_verification(background: BackgroundTasks, user: User = Depends(get_current_user),
                              db: AsyncSession = Depends(get_db)):
    if not user.email_verified:
        link = await _one_time_link(db, user, TokenPurpose.verify_email, 48, "verify-email")
        await db.commit()
        background.add_task(send_template, user.email, "verify_email", user.locale, link)
    return {"status": "accepted"}


@router.post("/forgot-password", status_code=202, dependencies=[rate_limit("forgot", 5, 3600)])
async def forgot_password(body: EmailIn, background: BackgroundTasks, db: AsyncSession = Depends(get_db)):
    # Hesabın var olup olmadığını sızdırmamak için her zaman 202 döner
    user = await db.scalar(select(User).where(User.email == body.email.lower()))
    if user and user.is_active:
        link = await _one_time_link(db, user, TokenPurpose.reset_password, 1, "reset-password")
        await db.commit()
        background.add_task(send_template, user.email, "reset_password", user.locale, link)
    return {"status": "accepted"}


async def _set_password(db: AsyncSession, user: User, new_password: str) -> None:
    ident = await db.scalar(select(AuthIdentity).where(AuthIdentity.user_id == user.id,
                                                       AuthIdentity.provider == AuthProvider.email))
    if ident:
        ident.password_hash = hash_password(new_password)
        ident.provider_uid = user.email
    else:  # sosyal girişle açılmış hesaba şifre ekleme
        db.add(AuthIdentity(user_id=user.id, provider=AuthProvider.email, provider_uid=user.email,
                            password_hash=hash_password(new_password)))
    await _revoke_all(db, user.id)


@router.post("/reset-password", status_code=204)
async def reset_password(body: ResetPasswordIn, background: BackgroundTasks, db: AsyncSession = Depends(get_db)):
    user = await _consume(db, body.token, TokenPurpose.reset_password)
    await _set_password(db, user, body.new_password)
    user.email_verified = True  # bağlantıya e-postadan ulaştı
    await db.commit()
    background.add_task(send_template, user.email, "password_changed", user.locale, None)
    return Response(status_code=204)


@router.post("/change-password", response_model=TokenPair, dependencies=[rate_limit("change_pw", 10, 3600, by="user")])
async def change_password(body: ChangePasswordIn, background: BackgroundTasks,
                          user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    ident = await db.scalar(select(AuthIdentity).where(AuthIdentity.user_id == user.id,
                                                       AuthIdentity.provider == AuthProvider.email))
    if ident and not verify_password(body.current_password or "", ident.password_hash):
        raise AppError(401, "invalid_credentials")
    await _set_password(db, user, body.new_password)
    tokens = await issue_tokens(db, user)  # diğer cihazlar düşer, bu cihaz yeni token alır
    await db.commit()
    background.add_task(send_template, user.email, "password_changed", user.locale, None)
    return tokens


@router.delete("/account", status_code=204)
async def delete_account(background: BackgroundTasks, user: User = Depends(get_current_user),
                         db: AsyncSession = Depends(get_db)):
    """KVKK/GDPR ve App Store gereği uygulama içinden kalıcı hesap silme."""
    photos = (await db.execute(select(Photo.original_key, Photo.variants).where(Photo.user_id == user.id))).all()
    keys = [orig for orig, _ in photos] + [v["key"] for _, variants in photos for v in (variants or {}).values()]
    keys += [k for k in (user.avatar_key, user.cover_key) if k]
    await db.delete(user)
    await db.commit()
    background.add_task(run_in_threadpool, storage.delete_objects, keys)
    return Response(status_code=204)
