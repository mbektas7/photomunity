"""Otomatik içerik denetimi. Varsayılan kapalıdır; MODERATION_PROVIDER=rekognition ile AWS Rekognition kullanılır."""
import logging
from dataclasses import dataclass, field
from functools import lru_cache

from app.core.config import get_settings

log = logging.getLogger("photomunity.moderation")
BLOCKED_TOP_LEVEL = {"Explicit Nudity", "Explicit", "Violence", "Graphic Violence", "Visually Disturbing", "Hate Symbols"}


@dataclass
class ModerationResult:
    safe: bool = True
    labels: list[str] = field(default_factory=list)


@lru_cache
def _rekognition():
    import boto3

    return boto3.client("rekognition")


def moderate(image_bytes: bytes) -> ModerationResult:
    """Senkron; çağıran run_in_threadpool ile çalıştırır. Görsel 5 MB altında olmalı (feed türevi kullanılır)."""
    s = get_settings()
    if s.moderation_provider != "rekognition":
        return ModerationResult()
    try:
        res = _rekognition().detect_moderation_labels(Image={"Bytes": image_bytes}, MinConfidence=s.moderation_min_confidence)
    except Exception:
        # Denetim servisi geçici olarak çalışmıyorsa yayını engellemeyiz; şikayet akışı devrede kalır
        log.exception("Moderasyon servisi hatası")
        return ModerationResult()
    labels = [l["Name"] for l in res.get("ModerationLabels", [])]
    parents = {l.get("ParentName") or l["Name"] for l in res.get("ModerationLabels", [])}
    return ModerationResult(safe=not (parents & BLOCKED_TOP_LEVEL), labels=labels)
