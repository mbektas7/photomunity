import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.v1 import auth, billing, communities, stats, contests, guides, map, messaging, moderation, notifications, photos, users
from app.core.config import get_settings
from app.core.errors import register_error_handlers
from app.services.ratelimit import limiter
from app.services.realtime import hub

log = logging.getLogger("photomunity")
settings = get_settings()


@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.arq = None
    if settings.environment != "test":
        await limiter.connect(settings.redis_url)
        await hub.start(settings.redis_url)
        try:
            from arq import create_pool
            from arq.connections import RedisSettings

            app.state.arq = await create_pool(RedisSettings.from_dsn(settings.redis_url))
        except Exception:
            log.warning("Redis'e bağlanılamadı; fotoğraflar API sürecinde işlenecek (yalnızca geliştirme için).")
    yield
    if app.state.arq:
        await app.state.arq.aclose()
    await hub.stop()


app = FastAPI(title=settings.app_name, version="0.1.0", lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=settings.cors_origins, allow_credentials=True,
                   allow_methods=["*"], allow_headers=["*"])
register_error_handlers(app)

for router in (auth.router, users.router, photos.router, notifications.router, moderation.router,
               communities.router, contests.router, messaging.router, map.router, guides.router, billing.router, stats.router):
    app.include_router(router, prefix=settings.api_prefix)


@app.get("/health", tags=["system"])
async def health():
    return {"status": "ok"}
