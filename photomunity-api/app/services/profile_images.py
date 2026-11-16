"""Avatar ve kapak işleme: kare/3:1 kırpma, WebP, EXIF'siz."""
import io

from PIL import Image, ImageOps

from app.core.config import Settings
from app.services.quality import ALLOWED_FORMATS  # noqa: F401  (HEIF açıcısını da kaydeder)

AVATAR_PX = 400
COVER_SIZE = (1800, 600)


class ProfileImageError(Exception):
    def __init__(self, code: str):
        self.code = code


def process_profile_image(data: bytes, kind: str, s: Settings) -> bytes:
    try:
        img = Image.open(io.BytesIO(data))
        img.load()
    except Exception:
        raise ProfileImageError("corrupt_image")
    if (img.format or "").upper() not in ALLOWED_FORMATS:
        raise ProfileImageError("unsupported_format")
    img = ImageOps.exif_transpose(img).convert("RGB")
    w, h = img.size
    if kind in ("avatar", "logo"):
        if min(w, h) < s.min_avatar_px:
            raise ProfileImageError("image_too_small")
        out = ImageOps.fit(img, (AVATAR_PX, AVATAR_PX), Image.Resampling.LANCZOS)
    else:
        if w < s.min_cover_width_px:
            raise ProfileImageError("image_too_small")
        out = ImageOps.fit(img, COVER_SIZE, Image.Resampling.LANCZOS)
    buf = io.BytesIO()
    out.save(buf, "WEBP", quality=86, method=4)
    return buf.getvalue()
