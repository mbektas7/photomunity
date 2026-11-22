import uuid
from datetime import datetime

import jwt
from fastapi import APIRouter, BackgroundTasks, Depends, Query, Request, Response, WebSocket, WebSocketDisconnect
from starlette.concurrency import run_in_threadpool
from sqlalchemy import and_, delete, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.api.deps import get_current_user
from app.api.v1.photos import _cards
from app.core import database
from app.core.config import get_settings
from app.core.database import get_db
from app.core.errors import AppError, request_locale
from app.core.security import as_aware, decode_token, utcnow
from app.models import Block, Conversation, ConversationRead, Message, MessageReaction, Photo, PhotoStatus, User
from app.schemas import (
    ConversationOut, GifOut, ImageVariant, LocationIn, MessageIn, MessageOut, MessagePage, MessageQuote, ReactionIn,
    ReactionOut, StartConversationIn, UserCard,
)
from app.services import giphy, storage
from app.services.moderation import moderate
from app.services.profile_images import ProfileImageError, process_news_image
from app.services.notifications import push_direct
from app.services.ratelimit import rate_limit
from app.services.realtime import hub

router = APIRouter(tags=["messaging"])
PENDING_LIMIT = 3  # istek kabul edilene kadar gönderilebilecek mesaj


def _pair(a: uuid.UUID, b: uuid.UUID) -> tuple[uuid.UUID, uuid.UUID]:
    return (a, b) if str(a) < str(b) else (b, a)


async def _blocked(db: AsyncSession, a: uuid.UUID, b: uuid.UUID) -> bool:
    return bool(await db.scalar(select(Block.blocker_id).where(or_(
        and_(Block.blocker_id == a, Block.blocked_id == b), and_(Block.blocker_id == b, Block.blocked_id == a)))))


async def _conversation(db: AsyncSession, cid: uuid.UUID, user: User) -> Conversation:
    c = await db.get(Conversation, cid)
    if not c or user.id not in (c.user_low_id, c.user_high_id):
        raise AppError(404, "not_found")
    # Reddedilmiş istek alıcıdan gizlenir
    if c.status == "declined" and c.requested_by != user.id:
        raise AppError(404, "not_found")
    return c


def _kind(m: Message) -> str:
    if m.image:
        return "image"
    if m.gif:
        return "gif"
    if m.photo_id:
        return "photo"
    if m.latitude is not None:
        return "location"
    return "text"


async def _message_outs(db: AsyncSession, messages: list[Message], viewer: User) -> list[MessageOut]:
    photos = [m.photo for m in messages if m.photo is not None and m.photo.status == PhotoStatus.published and not m.photo.hidden]
    if photos:
        # selectinload ile gelen fotoğrafların sahiplerini yükle
        ids = [p.id for p in photos]
        photos = list(await db.scalars(select(Photo).where(Photo.id.in_(ids)).options(selectinload(Photo.user))))
    cards = {c.id: c for c in await _cards(db, photos, viewer)} if photos else {}
    reply_ids = {m.reply_to_id for m in messages if m.reply_to_id}
    replies = {r.id: r for r in await db.scalars(select(Message).where(Message.id.in_(reply_ids)))} if reply_ids else {}
    mids = [m.id for m in messages]
    reactions: dict[uuid.UUID, list[ReactionOut]] = {}
    if mids:
        for r in await db.scalars(select(MessageReaction).where(MessageReaction.message_id.in_(mids))
                                  .order_by(MessageReaction.created_at)):
            reactions.setdefault(r.message_id, []).append(ReactionOut(user_id=r.user_id, emoji=r.emoji))
    out = []
    for m in messages:
        q = replies.get(m.reply_to_id) if m.reply_to_id else None
        out.append(MessageOut(
            id=m.id, conversation_id=m.conversation_id, sender_id=m.sender_id, body=m.body, created_at=m.created_at,
            photo=cards.get(m.photo_id) if m.photo_id else None,
            location=LocationIn(latitude=m.latitude, longitude=m.longitude, name=m.location_name) if m.latitude is not None else None,
            reply_to=MessageQuote(id=q.id, sender_id=q.sender_id, kind=_kind(q), preview=(q.body or "")[:140] or None) if q else None,
            image=ImageVariant(url=storage.public_url(m.image["key"]), width=m.image["width"], height=m.image["height"]) if m.image else None,
            gif=GifOut(**m.gif) if m.gif else None,
            reactions=reactions.get(m.id, []),
        ))
    return out


async def _last_read(db: AsyncSession, cid: uuid.UUID, user_id: uuid.UUID) -> datetime | None:
    return await db.scalar(select(ConversationRead.last_read_at).where(
        ConversationRead.conversation_id == cid, ConversationRead.user_id == user_id))


async def _unread(db: AsyncSession, c: Conversation, user_id: uuid.UUID) -> int:
    last = await _last_read(db, c.id, user_id)
    q = select(func.count()).select_from(Message).where(Message.conversation_id == c.id, Message.sender_id != user_id)
    if last:
        q = q.where(Message.created_at > last)
    return await db.scalar(q) or 0


async def _conversation_out(db: AsyncSession, c: Conversation, user: User) -> ConversationOut:
    other = await db.get(User, c.other(user.id))
    last = await db.scalar(select(Message).where(Message.conversation_id == c.id).order_by(Message.created_at.desc())
                           .options(selectinload(Message.photo)).limit(1))
    [last_out] = await _message_outs(db, [last], user) if last else [None]
    return ConversationOut(
        id=c.id, other=UserCard.model_validate(other), status=c.status,
        is_request_to_me=c.status == "request" and c.requested_by != user.id,
        last_message=last_out, unread=await _unread(db, c, user.id), last_message_at=c.last_message_at,
        other_last_read_at=await _last_read(db, c.id, other.id),
    )


def _visible_to(user_id: uuid.UUID):
    blocked = select(Block.blocked_id).where(Block.blocker_id == user_id)
    blockers = select(Block.blocker_id).where(Block.blocked_id == user_id)
    return and_(
        or_(Conversation.user_low_id == user_id, Conversation.user_high_id == user_id),
        Conversation.user_low_id.not_in(blocked), Conversation.user_high_id.not_in(blocked),
        Conversation.user_low_id.not_in(blockers), Conversation.user_high_id.not_in(blockers),
    )


@router.get("/conversations", response_model=list[ConversationOut])
async def list_conversations(folder: str = Query("inbox", pattern="^(inbox|requests)$"), limit: int = Query(50, le=100),
                             user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    q = select(Conversation).where(_visible_to(user.id))
    if folder == "requests":
        q = q.where(Conversation.status == "request", Conversation.requested_by != user.id)
    else:
        q = q.where(or_(Conversation.status == "accepted", Conversation.requested_by == user.id))
    rows = await db.scalars(q.order_by(Conversation.last_message_at.desc()).limit(limit))
    return [await _conversation_out(db, c, user) for c in rows]


@router.get("/messages/unread-count")
async def unread_count(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    inbox = requests = 0
    for c in await db.scalars(select(Conversation).where(_visible_to(user.id), Conversation.status != "declined")):
        n = await _unread(db, c, user.id)
        if c.status == "request" and c.requested_by != user.id:
            requests += 1 if n else 0
        else:
            inbox += n
    return {"inbox": inbox, "requests": requests}


async def _send(db: AsyncSession, background: BackgroundTasks, c: Conversation, sender: User, body: MessageIn) -> MessageOut:
    text = (body.body or "").strip()
    if not text and not body.photo_id and not body.location and not body.image_key and not body.gif:
        raise AppError(422, "empty_message")
    other_id = c.other(sender.id)
    if await _blocked(db, sender.id, other_id):
        raise AppError(403, "cannot_message")
    if body.photo_id:
        photo = await db.get(Photo, body.photo_id)
        if not photo or photo.status != PhotoStatus.published or photo.hidden:
            raise AppError(422, "photo_not_eligible")

    notify_type = "new_message"
    if c.status == "declined" and sender.id == c.requested_by:
        sent = await db.scalar(select(func.count()).select_from(Message).where(Message.conversation_id == c.id))
        if sent >= PENDING_LIMIT:
            raise AppError(429, "request_pending")
    if c.status == "request":
        if sender.id == c.requested_by:
            sent = await db.scalar(select(func.count()).select_from(Message).where(Message.conversation_id == c.id))
            if sent >= PENDING_LIMIT:
                raise AppError(429, "request_pending")
            notify_type = "message_request" if sent == 0 else ""
        else:
            c.status = "accepted"  # alıcının yanıtı isteği kabul etmek demektir
    deliver = c.status != "declined"  # reddedilmiş istekte mesaj saklanır ama alıcıya ulaşmaz

    if body.reply_to_id:
        target = await db.get(Message, body.reply_to_id)
        if not target or target.conversation_id != c.id:
            raise AppError(404, "not_found")
    gif = await giphy.fetch(body.gif.id, body.gif.kind) if body.gif else None
    image = await _message_image(c, sender, body.image_key, background) if body.image_key else None

    msg = Message(conversation_id=c.id, sender_id=sender.id, body=text or None, photo_id=body.photo_id,
                  latitude=body.location.latitude if body.location else None,
                  longitude=body.location.longitude if body.location else None,
                  location_name=body.location.name if body.location else None,
                  reply_to_id=body.reply_to_id, image=image, gif=gif)
    db.add(msg)
    c.last_message_at = utcnow()
    await _mark_read(db, c.id, sender.id)
    await db.commit()
    msg = await db.scalar(select(Message).where(Message.id == msg.id).options(selectinload(Message.photo)))
    [out] = await _message_outs(db, [msg], sender)

    recipients = [sender.id] + ([other_id] if deliver else [])
    background.add_task(hub.publish, recipients, {"type": "message", "conversation_id": str(c.id), "status": c.status,
                                                  "message": out.model_dump(mode="json")})
    if deliver and notify_type:
        preview = text[:80] if text else ("📷" if body.photo_id or image else "GIF" if gif else "📍")
        background.add_task(push_direct, other_id, notify_type, sender.display_name,
                            {"conversation_id": str(c.id), "username": sender.username}, {"preview": preview})
    return out


async def _message_image(c: Conversation, sender: User, key: str, background: BackgroundTasks) -> dict:
    """Galeriden/kameradan yüklenen görsel: kırpılmaz, uzun kenar en fazla 2048 px, WebP, EXIF'siz, denetimden geçer.
    Yalnız bu sohbette gösterilir; adresi tahmin edilemez."""
    if not key.startswith(f"uploads/{sender.id}/") or ".." in key:
        raise AppError(400, "invalid_key")
    try:
        data = await run_in_threadpool(storage.get_object, key)
    except Exception:
        raise AppError(400, "storage_missing")
    background.add_task(run_in_threadpool, storage.delete_objects, [key])
    try:
        webp, w, h = await run_in_threadpool(process_news_image, data)
    except ProfileImageError as e:
        raise AppError(422, e.code)
    if not (await run_in_threadpool(moderate, webp)).safe:
        raise AppError(422, "inappropriate_content")
    new_key = f"photos/messages/{c.id}/{uuid.uuid4().hex}.webp"
    await run_in_threadpool(storage.put_object, new_key, webp, "image/webp")
    return {"key": new_key, "width": w, "height": h}


async def _mark_read(db: AsyncSession, cid: uuid.UUID, user_id: uuid.UUID) -> None:
    row = await db.get(ConversationRead, (cid, user_id))
    if row:
        row.last_read_at = utcnow()
    else:
        db.add(ConversationRead(conversation_id=cid, user_id=user_id, last_read_at=utcnow()))


@router.post("/conversations", response_model=ConversationOut, status_code=201,
             dependencies=[rate_limit("conversation_start", 20, 86400, by="user")])
async def start_conversation(body: StartConversationIn, background: BackgroundTasks, user: User = Depends(get_current_user),
                             db: AsyncSession = Depends(get_db)):
    """Var olan sohbete yazar ya da yenisini başlatır. Yeni sohbet yalnızca herkese açık profillere başlatılabilir."""
    other = await db.scalar(select(User).where(User.username == body.username.lower(), User.is_active.is_(True)))
    if not other or other.id == user.id:
        raise AppError(404, "not_found")
    low, high = _pair(user.id, other.id)
    c = await db.scalar(select(Conversation).where(Conversation.user_low_id == low, Conversation.user_high_id == high))
    if c is None:
        if not other.is_public or await _blocked(db, user.id, other.id):
            raise AppError(403, "cannot_message")
        c = Conversation(id=uuid.uuid4(), user_low_id=low, user_high_id=high, requested_by=user.id, status="request")
        db.add(c)
        await db.flush()
    await _send(db, background, c, user, body)
    return await _conversation_out(db, c, user)


@router.get("/conversations/with/{username}", response_model=ConversationOut | None)
async def conversation_with(username: str, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    other = await db.scalar(select(User).where(User.username == username.lower()))
    if not other:
        raise AppError(404, "not_found")
    low, high = _pair(user.id, other.id)
    c = await db.scalar(select(Conversation).where(Conversation.user_low_id == low, Conversation.user_high_id == high))
    if not c or (c.status == "declined" and c.requested_by != user.id):
        return None
    return await _conversation_out(db, c, user)


@router.get("/conversations/{cid}", response_model=ConversationOut)
async def get_conversation(cid: uuid.UUID, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    return await _conversation_out(db, await _conversation(db, cid, user), user)


@router.get("/conversations/{cid}/messages", response_model=MessagePage)
async def list_messages(cid: uuid.UUID, before: datetime | None = None, limit: int = Query(40, le=100),
                        user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    c = await _conversation(db, cid, user)
    q = select(Message).where(Message.conversation_id == c.id).options(selectinload(Message.photo))
    if before:
        q = q.where(Message.created_at < before)
    rows = list(await db.scalars(q.order_by(Message.created_at.desc()).limit(limit + 1)))
    page = rows[:limit]
    return MessagePage(items=list(reversed(await _message_outs(db, page, user))),
                       next_cursor=page[-1].created_at.isoformat() if len(rows) > limit else None)


@router.post("/conversations/{cid}/messages", response_model=MessageOut, status_code=201,
             dependencies=[rate_limit("message", 60, 60, by="user")])
async def send_message(cid: uuid.UUID, body: MessageIn, background: BackgroundTasks, user: User = Depends(get_current_user),
                       db: AsyncSession = Depends(get_db)):
    return await _send(db, background, await _conversation(db, cid, user), user, body)


@router.post("/conversations/{cid}/accept", response_model=ConversationOut)
async def accept(cid: uuid.UUID, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    c = await _conversation(db, cid, user)
    if c.status == "request" and c.requested_by != user.id:
        c.status = "accepted"
        await db.commit()
    return await _conversation_out(db, c, user)


@router.post("/conversations/{cid}/decline", status_code=204)
async def decline(cid: uuid.UUID, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    c = await _conversation(db, cid, user)
    if c.status == "request" and c.requested_by != user.id:
        c.status = "declined"  # gönderen bilgilendirilmez; istek alıcıdan kaybolur
        await db.commit()
    return Response(status_code=204)


@router.post("/conversations/{cid}/read", status_code=204)
async def mark_read(cid: uuid.UUID, background: BackgroundTasks, user: User = Depends(get_current_user),
                    db: AsyncSession = Depends(get_db)):
    c = await _conversation(db, cid, user)
    await _mark_read(db, c.id, user.id)
    await db.commit()
    background.add_task(hub.publish, [c.other(user.id)], {"type": "read", "conversation_id": str(c.id), "at": utcnow().isoformat()})
    return Response(status_code=204)


# ---------- Tepkiler ----------
async def _publish_reactions(db: AsyncSession, background: BackgroundTasks, c: Conversation, m: Message) -> list[ReactionOut]:
    rows = await db.scalars(select(MessageReaction).where(MessageReaction.message_id == m.id).order_by(MessageReaction.created_at))
    reactions = [ReactionOut(user_id=r.user_id, emoji=r.emoji) for r in rows]
    background.add_task(hub.publish, [c.user_low_id, c.user_high_id], {
        "type": "reaction", "conversation_id": str(c.id), "message_id": str(m.id),
        "reactions": [r.model_dump(mode="json") for r in reactions]})
    return reactions


async def _message(db: AsyncSession, cid: uuid.UUID, mid: uuid.UUID, user: User) -> tuple[Conversation, Message]:
    c = await _conversation(db, cid, user)
    m = await db.get(Message, mid)
    if not m or m.conversation_id != c.id:
        raise AppError(404, "not_found")
    if await _blocked(db, user.id, c.other(user.id)):
        raise AppError(403, "cannot_message")
    return c, m


@router.put("/conversations/{cid}/messages/{mid}/reaction", response_model=list[ReactionOut],
            dependencies=[rate_limit("reaction", 120, 60, by="user")])
async def react(cid: uuid.UUID, mid: uuid.UUID, body: ReactionIn, background: BackgroundTasks,
                user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    """Mesaja tepki ekler ya da değiştirir (kişi başına bir tepki)."""
    c, m = await _message(db, cid, mid, user)
    row = await db.get(MessageReaction, (m.id, user.id))
    if row:
        row.emoji = body.emoji
    else:
        db.add(MessageReaction(message_id=m.id, user_id=user.id, emoji=body.emoji))
    await db.commit()
    return await _publish_reactions(db, background, c, m)


@router.delete("/conversations/{cid}/messages/{mid}/reaction", response_model=list[ReactionOut])
async def unreact(cid: uuid.UUID, mid: uuid.UUID, background: BackgroundTasks,
                  user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    c, m = await _message(db, cid, mid, user)
    await db.execute(delete(MessageReaction).where(MessageReaction.message_id == m.id, MessageReaction.user_id == user.id))
    await db.commit()
    return await _publish_reactions(db, background, c, m)


# ---------- GIF ve çıkartma (GIPHY) ----------
@router.get("/gifs", response_model=list[GifOut], dependencies=[rate_limit("gifs", 120, 60, by="user")])
async def gifs(request: Request, q: str | None = Query(None, max_length=50), kind: str = Query("gif", pattern="^(gif|sticker)$"),
               offset: int = Query(0, ge=0, le=500), limit: int = Query(24, ge=1, le=50),
               _: User = Depends(get_current_user)):
    """Arama yoksa popüler olanlar. GIPHY anahtarı tanımlı değilse 503 gifs_unavailable."""
    return await giphy.search((q or "").strip() or None, kind, limit, offset, request_locale(request))


# ---------- Engelleme ----------
@router.post("/users/{username}/block", status_code=204)
async def block(username: str, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    from app.models import Follow

    target = await db.scalar(select(User).where(User.username == username.lower()))
    if not target or target.id == user.id:
        raise AppError(404, "not_found")
    if not await db.get(Block, (user.id, target.id)):
        db.add(Block(blocker_id=user.id, blocked_id=target.id))
    # Engelleme karşılıklı takibi de kaldırır
    await db.execute(delete(Follow).where(or_(and_(Follow.follower_id == user.id, Follow.followee_id == target.id),
                                              and_(Follow.follower_id == target.id, Follow.followee_id == user.id))))
    await db.commit()
    return Response(status_code=204)


@router.delete("/users/{username}/block", status_code=204)
async def unblock(username: str, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    target = await db.scalar(select(User).where(User.username == username.lower()))
    if target:
        await db.execute(delete(Block).where(Block.blocker_id == user.id, Block.blocked_id == target.id))
        await db.commit()
    return Response(status_code=204)


@router.get("/me/blocks", response_model=list[UserCard])
async def my_blocks(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    rows = await db.scalars(select(User).join(Block, Block.blocked_id == User.id).where(Block.blocker_id == user.id))
    return [UserCard.model_validate(u) for u in rows]


# ---------- Gerçek zamanlı ----------
@router.post("/realtime/ticket")
async def realtime_ticket(user: User = Depends(get_current_user)):
    """Web istemcisi için 60 saniyelik WebSocket bileti (erişim token'ı tarayıcıya verilmez)."""
    s = get_settings()
    from datetime import timedelta

    token = jwt.encode({"sub": str(user.id), "type": "ws", "exp": utcnow() + timedelta(seconds=60)}, s.jwt_secret, algorithm=s.jwt_algorithm)
    return {"ticket": token}


@router.websocket("/ws")
async def websocket(ws: WebSocket, ticket: str | None = None, token: str | None = None):
    """Bağlantı: ?ticket=<bilet> (web) ya da ?token=<erişim token'ı> (mobil)."""
    try:
        payload = decode_token(ticket, "ws") if ticket else decode_token(token or "", "access")
        user_id = uuid.UUID(payload["sub"])
    except (jwt.PyJWTError, ValueError, KeyError):
        await ws.close(code=4401)
        return
    async with database.SessionLocal() as db:
        user = await db.get(User, user_id)
        if not user or not user.is_active:
            await ws.close(code=4401)
            return
    await ws.accept()
    hub.connect(user_id, ws)
    try:
        while True:
            msg = await ws.receive_text()
            if msg == "ping":
                await ws.send_text('{"type":"pong"}')
    except WebSocketDisconnect:
        pass
    finally:
        hub.disconnect(user_id, ws)
