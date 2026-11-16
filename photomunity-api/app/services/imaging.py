"""Yayın türevleri: EXIF'siz (dolayısıyla GPS'siz) WebP kopyalar. Renk profili korunur."""
import io
from dataclasses import dataclass

from PIL import Image, ImageOps

VARIANT_SIZES = {"thumb": 480, "feed": 1440, "full": 2560}


@dataclass
class Variant:
    data: bytes
    width: int
    height: int


def build_variants(original: Image.Image) -> dict[str, Variant]:
    icc = original.info.get("icc_profile")
    base = ImageOps.exif_transpose(original).convert("RGB")
    out: dict[str, Variant] = {}
    for name, edge in VARIANT_SIZES.items():
        img = base.copy()
        img.thumbnail((edge, edge), Image.Resampling.LANCZOS)
        buf = io.BytesIO()
        save_kwargs = {"quality": 86, "method": 4}
        if icc:
            save_kwargs["icc_profile"] = icc
        img.save(buf, "WEBP", **save_kwargs)
        out[name] = Variant(buf.getvalue(), *img.size)
    return out
