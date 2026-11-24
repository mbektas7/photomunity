"""Koleksiyonlar (seriler): profilde sahibinin kendi karelerinden sıralı seçkiler."""
import uuid

from fastapi import APIRouter, Depends, Query, Response
from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.api.deps import can_view_photos, get_current_user, get_optional_user
from app.api.v1.photos import _cards, _images
from app.core.database import get_db
from app.core.errors import AppError
from app.core.security import utcnow
from app.models import Collection, CollectionItem, Photo, PhotoStatus, User
from app.schemas import (
    CollectionCard, CollectionIn, CollectionOrderIn, CollectionOut, CollectionPhotoIn, CollectionPhotosIn, CollectionUpdate,
    UserCard,
)

router = APIRouter(tags=["collections"])
MAX_COLLECTIONS = 50
MAX_ITEMS = 200


def _live_items(collection_ids):
    """Yayında ve gizlenmemiş karelere ait öğeler, koleksiyondaki sıraya göre."""
    return (select(CollectionItem.collection_id, Photo).join(Photo, Photo.id == CollectionItem.photo_id)
            .where(CollectionItem.collection_id.in_(collection_ids), Photo.status == PhotoStatus.published,
                   Photo.hidden.is_(False))
            .order_by(CollectionItem.collection_id, CollectionItem.position, CollectionItem.photo_id))


async def _cards_for(db: AsyncSession, cols: list[Collection], contains: uuid.UUID | None = None,
                     mark: bool = False) -> list[CollectionCard]:
    ids = [c.id for c in cols]
    items: dict[uuid.UUID, list[Photo]] = {i: [] for i in ids}
    if ids:
        for cid, photo in (await db.execute(_live_items(ids))).all():
            items[cid].append(photo)
    return [CollectionCard(id=c.id, title=c.title, description=c.description, photo_count=len(items[c.id]),
                           covers=[_images(p) for p in items[c.id][:3]], position=c.position, updated_at=c.updated_at,
                           contains_photo=(any(p.id == contains for p in items[c.id]) if mark else None))
            for c in cols]


def _ordered(q):
    return q.order_by(Collection.position, Collection.created_at)


async def _owned(db: AsyncSession, collection_id: uuid.UUID, user: User) -> Collection:
    c = await db.get(Collection, collection_id)
    if not c or c.user_id != user.id:
        raise AppError(404, "not_found")
    return c


async def _eligible(db: AsyncSession, photo_ids: list[uuid.UUID], user: User) -> list[uuid.UUID]:
    """Tekrarları atar (ilk görülen sıra korunur); her kare sahibine ait, yayında ve gizlenmemiş olmalı."""
    unique = list(dict.fromkeys(photo_ids))
    if not unique:
        return []
    ok = set(await db.scalars(select(Photo.id).where(Photo.id.in_(unique), Photo.user_id == user.id,
                                                     Photo.status == PhotoStatus.published, Photo.hidden.is_(False))))
    if len(ok) != len(unique):
        raise AppError(422, "photo_not_eligible")
    return unique


async def _set_items(db: AsyncSession, c: Collection, photo_ids: list[uuid.UUID]) -> None:
    await db.execute(delete(CollectionItem).where(CollectionItem.collection_id == c.id))
    for i, pid in enumerate(photo_ids):
        db.add(CollectionItem(collection_id=c.id, photo_id=pid, position=i))
    c.updated_at = utcnow()


async def collection_out(db: AsyncSession, c: Collection, viewer: User | None) -> CollectionOut:
    owner = await db.get(User, c.user_id)
    [card] = await _cards_for(db, [c])
    photos = [p for _, p in (await db.execute(_live_items([c.id]).options(selectinload(Photo.user)))).all()]
    return CollectionOut(**card.model_dump(), owner=UserCard.model_validate(owner),
                         is_mine=viewer is not None and viewer.id == c.user_id,
                         photos=await _cards(db, photos, viewer), created_at=c.created_at)


@router.get("/users/{username}/collections", response_model=list[CollectionCard])
async def user_collections(username: str, viewer: User | None = Depends(get_optional_user), db: AsyncSession = Depends(get_db)):
    owner = await db.scalar(select(User).where(User.username == username.lower(), User.is_active.is_(True)))
    if not owner:
        raise AppError(404, "not_found")
    if not await can_view_photos(db, viewer, owner):
        raise AppError(403, "private_profile")
    cols = list(await db.scalars(_ordered(select(Collection).where(Collection.user_id == owner.id))))
    return await _cards_for(db, cols)


@router.get("/me/collections", response_model=list[CollectionCard])
async def my_collections(photo_id: uuid.UUID | None = None, user: User = Depends(get_current_user),
                         db: AsyncSession = Depends(get_db)):
    """Koleksiyonlarım. photo_id verilirse her kartta contains_photo dolar ("koleksiyona ekle" sayfası için)."""
    cols = list(await db.scalars(_ordered(select(Collection).where(Collection.user_id == user.id))))
    return await _cards_for(db, cols, contains=photo_id, mark=photo_id is not None)


@router.put("/me/collections/order", response_model=list[CollectionCard])
async def reorder_collections(body: CollectionOrderIn, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    """Profilde koleksiyon sırası. Listede olmayanlar sona, mevcut sıralarıyla eklenir."""
    cols = list(await db.scalars(_ordered(select(Collection).where(Collection.user_id == user.id))))
    by_id = {c.id: c for c in cols}
    order = [i for i in dict.fromkeys(body.collection_ids) if i in by_id]
    order += [c.id for c in cols if c.id not in order]
    for i, cid in enumerate(order):
        by_id[cid].position = i
    await db.commit()
    return await _cards_for(db, [by_id[i] for i in order])


@router.get("/collections/{collection_id}", response_model=CollectionOut)
async def get_collection(collection_id: uuid.UUID, viewer: User | None = Depends(get_optional_user),
                         db: AsyncSession = Depends(get_db)):
    c = await db.get(Collection, collection_id)
    owner = await db.get(User, c.user_id) if c else None
    if not c or not owner or not owner.is_active:
        raise AppError(404, "not_found")
    if not await can_view_photos(db, viewer, owner):
        raise AppError(403, "private_profile")
    return await collection_out(db, c, viewer)


@router.post("/collections", response_model=CollectionOut, status_code=201)
async def create_collection(body: CollectionIn, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    count = await db.scalar(select(func.count()).select_from(Collection).where(Collection.user_id == user.id)) or 0
    if count >= MAX_COLLECTIONS:
        raise AppError(409, "collection_limit")
    photo_ids = await _eligible(db, body.photo_ids, user)
    c = Collection(id=uuid.uuid4(), user_id=user.id, title=body.title.strip(),
                   description=(body.description or "").strip() or None, position=count)
    db.add(c)
    await db.flush()
    await _set_items(db, c, photo_ids)
    await db.commit()
    return await collection_out(db, c, user)


@router.patch("/collections/{collection_id}", response_model=CollectionOut)
async def update_collection(collection_id: uuid.UUID, body: CollectionUpdate, user: User = Depends(get_current_user),
                            db: AsyncSession = Depends(get_db)):
    c = await _owned(db, collection_id, user)
    data = body.model_dump(exclude_unset=True)
    if data.get("title"):
        c.title = data["title"].strip()
    if "description" in data:
        c.description = (data["description"] or "").strip() or None
    c.updated_at = utcnow()
    await db.commit()
    return await collection_out(db, c, user)


@router.delete("/collections/{collection_id}", status_code=204)
async def delete_collection(collection_id: uuid.UUID, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    c = await _owned(db, collection_id, user)
    await db.execute(delete(CollectionItem).where(CollectionItem.collection_id == c.id))
    await db.delete(c)
    await db.commit()
    return Response(status_code=204)


@router.put("/collections/{collection_id}/photos", response_model=CollectionOut)
async def replace_photos(collection_id: uuid.UUID, body: CollectionPhotosIn, user: User = Depends(get_current_user),
                         db: AsyncSession = Depends(get_db)):
    """Koleksiyonun karelerini ve sırasını verilen listeyle değiştirir (en fazla 200)."""
    c = await _owned(db, collection_id, user)
    await _set_items(db, c, await _eligible(db, body.photo_ids, user))
    await db.commit()
    return await collection_out(db, c, user)


@router.post("/collections/{collection_id}/photos", response_model=CollectionOut)
async def add_photo(collection_id: uuid.UUID, body: CollectionPhotoIn, user: User = Depends(get_current_user),
                    db: AsyncSession = Depends(get_db)):
    """Kareyi sona ekler; zaten varsa değişiklik yapmaz."""
    c = await _owned(db, collection_id, user)
    await _eligible(db, [body.photo_id], user)
    if not await db.get(CollectionItem, (c.id, body.photo_id)):
        count = await db.scalar(select(func.count()).select_from(CollectionItem).where(CollectionItem.collection_id == c.id)) or 0
        if count >= MAX_ITEMS:
            raise AppError(409, "collection_full")
        last = await db.scalar(select(func.max(CollectionItem.position)).where(CollectionItem.collection_id == c.id))
        db.add(CollectionItem(collection_id=c.id, photo_id=body.photo_id, position=(last if last is not None else -1) + 1))
        c.updated_at = utcnow()
        await db.commit()
    return await collection_out(db, c, user)


@router.delete("/collections/{collection_id}/photos/{photo_id}", status_code=204)
async def remove_photo(collection_id: uuid.UUID, photo_id: uuid.UUID, user: User = Depends(get_current_user),
                       db: AsyncSession = Depends(get_db)):
    c = await _owned(db, collection_id, user)
    await db.execute(delete(CollectionItem).where(CollectionItem.collection_id == c.id, CollectionItem.photo_id == photo_id))
    c.updated_at = utcnow()
    await db.commit()
    return Response(status_code=204)
