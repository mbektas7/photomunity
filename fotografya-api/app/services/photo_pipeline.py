"""Yüklenen fotoğrafı işler: kalite kontrol -> EXIF -> türevler -> yayın."""
import logging
import uuid

from starlette.concurrency import run_in_threadpool

from app.core import database
from app.core.config import get_settings
from app.core.security import utcnow
from app.models import Photo, PhotoExif, PhotoStatus
from app.services import storage
from app.services.exif import extract_exif
from app.services.imaging import build_variants
from app.services.moderation import moderate
from app.services.notifications import deliver, notify
from app.services.quality import analyze_image

log = logging.getLogger("fotografya.pipeline")


async def process_photo(photo_id: uuid.UUID) -> PhotoStatus | None:
    s = get_settings()
    async with database.SessionLocal() as db:
        photo = await db.get(Photo, photo_id)
        if not photo or photo.status != PhotoStatus.processing:
            return None

        try:
            data = await run_in_threadpool(storage.get_object, photo.original_key)
        except Exception:
            log.exception("Orijinal okunamadı: %s", photo.original_key)
            photo.status, photo.rejection_codes = PhotoStatus.rejected, ["storage_missing"]
            await db.commit()
            return photo.status

        report, image = await run_in_threadpool(analyze_image, data, s)
        photo.size_bytes, photo.width, photo.height = report.size_bytes, report.width, report.height
        photo.quality = report.as_dict()

        async def reject(codes: list[str]) -> PhotoStatus:
            photo.status, photo.rejection_codes = PhotoStatus.rejected, codes
            n = await notify(db, user_id=photo.user_id, type="photo_rejected", photo_id=photo.id)
            await db.commit()
            # Reddedilen orijinali tutmanın anlamı yok
            await run_in_threadpool(storage.delete_objects, [photo.original_key])
            if n:
                await deliver([n.id])
            return photo.status

        if not report.passed or image is None:
            return await reject(report.codes)

        exif = await run_in_threadpool(extract_exif, image)
        variants = await run_in_threadpool(build_variants, image)
        verdict = await run_in_threadpool(moderate, variants["feed"].data)
        if not verdict.safe:
            photo.quality = {**photo.quality, "moderation_labels": verdict.labels}
            return await reject(["inappropriate_content"])
        stored = {}
        for name, v in variants.items():
            key = f"photos/{photo.user_id}/{photo.id}/{name}.webp"
            await run_in_threadpool(storage.put_object, key, v.data, "image/webp")
            stored[name] = {"key": key, "width": v.width, "height": v.height}

        db.add(PhotoExif(photo_id=photo.id, **exif))
        photo.variants = stored
        photo.rejection_codes = []
        photo.status = PhotoStatus.published
        photo.published_at = utcnow()
        n = await notify(db, user_id=photo.user_id, type="photo_published", photo_id=photo.id)
        await db.commit()
        if n:
            await deliver([n.id])
        return photo.status
