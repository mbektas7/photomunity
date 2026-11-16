import uuid

import jwt
from fastapi import Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.errors import AppError
from app.core.security import decode_token
from app.models import Follow, User

bearer = HTTPBearer(auto_error=False)


async def _user_from(creds: HTTPAuthorizationCredentials | None, db: AsyncSession) -> User | None:
    if not creds:
        return None
    try:
        payload = decode_token(creds.credentials, "access")
        user = await db.get(User, uuid.UUID(payload["sub"]))
    except (jwt.PyJWTError, ValueError, KeyError):
        raise AppError(401, "invalid_token")
    if not user or not user.is_active:
        raise AppError(401, "invalid_token")
    return user


async def get_current_user(creds=Depends(bearer), db: AsyncSession = Depends(get_db)) -> User:
    user = await _user_from(creds, db)
    if not user:
        raise AppError(401, "not_authenticated")
    return user


async def get_optional_user(creds=Depends(bearer), db: AsyncSession = Depends(get_db)) -> User | None:
    return await _user_from(creds, db)


async def is_following(db: AsyncSession, follower_id: uuid.UUID, followee_id: uuid.UUID) -> bool:
    return bool(await db.scalar(
        select(Follow.follower_id).where(Follow.follower_id == follower_id, Follow.followee_id == followee_id)
    ))


async def can_view_photos(db: AsyncSession, viewer: User | None, owner: User) -> bool:
    """Herkese açık profil: herkes. Kapalı profil: sahibi ve takipçileri (takipte onay yok)."""
    if owner.is_public or (viewer and viewer.id == owner.id):
        return True
    return bool(viewer) and await is_following(db, viewer.id, owner.id)
