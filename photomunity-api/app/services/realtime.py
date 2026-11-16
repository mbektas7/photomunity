"""Gerçek zamanlı olaylar (yeni mesaj, okundu bilgisi).

Her API süreci kendi WebSocket bağlantılarını tutar. Redis varsa olaylar bir pub/sub kanalından
tüm süreçlere dağıtılır; yoksa yalnızca aynı süreçteki bağlantılara gider (tek süreçli geliştirme).
"""
import asyncio
import json
import logging
import uuid
from collections import defaultdict

from fastapi import WebSocket

log = logging.getLogger("photomunity.realtime")
CHANNEL = "fg:realtime"


class Hub:
    def __init__(self) -> None:
        self.local: dict[uuid.UUID, set[WebSocket]] = defaultdict(set)
        self.redis = None
        self._task: asyncio.Task | None = None

    async def start(self, redis_url: str) -> None:
        try:
            from redis.asyncio import from_url

            self.redis = from_url(redis_url)
            await self.redis.ping()
            self._task = asyncio.create_task(self._listen())
        except Exception:
            self.redis = None
            log.warning("Redis yok; gerçek zamanlı olaylar yalnızca bu süreçteki bağlantılara gider.")

    async def stop(self) -> None:
        if self._task:
            self._task.cancel()

    async def _listen(self) -> None:
        pubsub = self.redis.pubsub()
        await pubsub.subscribe(CHANNEL)
        async for msg in pubsub.listen():
            if msg.get("type") != "message":
                continue
            try:
                payload = json.loads(msg["data"])
                await self._deliver_local([uuid.UUID(u) for u in payload["users"]], payload["event"])
            except Exception:
                log.exception("Gerçek zamanlı olay işlenemedi")

    def connect(self, user_id: uuid.UUID, ws: WebSocket) -> None:
        self.local[user_id].add(ws)

    def disconnect(self, user_id: uuid.UUID, ws: WebSocket) -> None:
        self.local[user_id].discard(ws)
        if not self.local[user_id]:
            self.local.pop(user_id, None)

    async def publish(self, user_ids: list[uuid.UUID], event: dict) -> None:
        if self.redis is not None:
            try:
                await self.redis.publish(CHANNEL, json.dumps({"users": [str(u) for u in user_ids], "event": event}, default=str))
                return
            except Exception:
                log.exception("Redis yayını başarısız; yerel teslim deneniyor")
        await self._deliver_local(user_ids, event)

    async def _deliver_local(self, user_ids: list[uuid.UUID], event: dict) -> None:
        data = json.dumps(event, default=str)
        for uid in user_ids:
            for ws in list(self.local.get(uid, ())):
                try:
                    await ws.send_text(data)
                except Exception:
                    self.disconnect(uid, ws)


hub = Hub()
