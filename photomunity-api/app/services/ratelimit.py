"""Sabit pencereli istek sınırlayıcı. Redis varsa çok süreçli/çok sunuculu çalışır; yoksa süreç belleğine düşer."""
import logging
import time

from fastapi import Depends, Request

from app.core.config import get_settings
from app.core.errors import AppError

log = logging.getLogger("photomunity.ratelimit")


class RateLimiter:
    def __init__(self) -> None:
        self.redis = None
        self._mem: dict[str, tuple[int, float]] = {}

    async def connect(self, url: str) -> None:
        try:
            from redis.asyncio import from_url

            client = from_url(url)
            await client.ping()
            self.redis = client
        except Exception:
            log.warning("Redis yok; istek sınırları yalnızca bu süreçte uygulanacak.")

    async def hit(self, key: str, limit: int, window: int) -> bool:
        if self.redis is not None:
            try:
                pipe = self.redis.pipeline()
                pipe.incr(key)
                pipe.expire(key, window, nx=True)
                count, _ = await pipe.execute()
                return int(count) <= limit
            except Exception:
                log.exception("Redis sınırlayıcı hatası; istek geçiriliyor")
                return True
        now = time.monotonic()
        count, reset = self._mem.get(key, (0, now + window))
        if now > reset:
            count, reset = 0, now + window
        count += 1
        self._mem[key] = (count, reset)
        if len(self._mem) > 50_000:  # bellek koruması
            self._mem = {k: v for k, v in self._mem.items() if v[1] > now}
        return count <= limit

    def reset(self) -> None:
        self._mem.clear()


limiter = RateLimiter()


def client_ip(request: Request) -> str:
    if get_settings().trust_proxy_headers:
        forwarded = request.headers.get("x-forwarded-for")
        if forwarded:
            return forwarded.split(",")[0].strip()
    return request.client.host if request.client else "unknown"


def rate_limit(scope: str, limit: int, window_seconds: int, by: str = "ip", pro_limit: int | None = None):
    """Route bağımlılığı: `dependencies=[rate_limit("login", 10, 300)]`. by="user" oturumdaki kullanıcıya göre sayar."""
    from app.api.deps import get_optional_user  # döngüsel içe aktarmayı önlemek için

    async def dependency(request: Request, user=Depends(get_optional_user)):
        if not get_settings().rate_limit_enabled:
            return
        ident = str(user.id) if by == "user" and user is not None else client_ip(request)
        effective = pro_limit if pro_limit and user is not None and user.is_pro else limit
        if not await limiter.hit(f"rl:{scope}:{ident}", effective, window_seconds):
            raise AppError(429, "too_many_requests")

    return Depends(dependency)
