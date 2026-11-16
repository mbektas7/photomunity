"""Yükleme kalite kontrolü: boyut, format, çözünürlük, netlik ve pozlama."""
import io
from dataclasses import asdict, dataclass, field

import cv2
import numpy as np
import pillow_heif
from PIL import Image, ImageOps

from app.core.config import Settings

pillow_heif.register_heif_opener()
Image.MAX_IMAGE_PIXELS = 200_000_000  # ~200 MP üstü decompression-bomb koruması

ALLOWED_FORMATS = {"JPEG", "MPO", "PNG", "WEBP", "HEIF"}
ANALYSIS_EDGE = 1024
GRID = 8


@dataclass
class QualityReport:
    passed: bool
    codes: list[str] = field(default_factory=list)
    width: int = 0
    height: int = 0
    size_bytes: int = 0
    format: str | None = None
    sharpness: float | None = None
    highlight_clip: float | None = None
    shadow_clip: float | None = None

    def as_dict(self) -> dict:
        return asdict(self)


def _analysis_gray(img: Image.Image) -> np.ndarray:
    small = img.convert("L")
    small.thumbnail((ANALYSIS_EDGE, ANALYSIS_EDGE), Image.Resampling.LANCZOS)
    return np.asarray(small, dtype=np.uint8)


def tile_sharpness(gray: np.ndarray) -> float:
    """Görüntüyü 8x8 karoya böler, her karoda Laplacian varyansını ölçer ve 90. yüzdeliği döndürür.

    Tek bir global değer yerine karo kullanmak, arka planı bilinçli olarak bulanık portreleri
    ve büyük kısmı karanlık gökyüzü olan astro kareleri haksız yere reddetmeyi önler:
    kadrajın netlik taşıyan bölgesi yeterince keskinse foto geçer.
    """
    lap = cv2.Laplacian(gray, cv2.CV_64F)
    th, tw = max(gray.shape[0] // GRID, 1), max(gray.shape[1] // GRID, 1)
    values = [
        float(lap[y : y + th, x : x + tw].var())
        for y in range(0, th * GRID, th)
        for x in range(0, tw * GRID, tw)
        if lap[y : y + th, x : x + tw].size
    ]
    return float(np.percentile(values, 90)) if values else 0.0


def analyze_image(data: bytes, s: Settings) -> tuple[QualityReport, Image.Image | None]:
    """Görseli analiz eder. Dönen Image, EXIF'i korunmuş ve döndürülmemiş orijinaldir."""
    report = QualityReport(passed=False, size_bytes=len(data))

    if report.size_bytes > s.max_file_bytes:
        report.codes.append("file_too_large")
        return report, None
    if report.size_bytes < s.min_file_bytes:
        report.codes.append("file_too_small")

    try:
        img = Image.open(io.BytesIO(data))
        img.load()
    except Exception:
        report.codes.append("corrupt_image")
        return report, None

    report.format = (img.format or "").upper()
    if report.format not in ALLOWED_FORMATS:
        report.codes.append("unsupported_format")
        return report, None

    oriented = ImageOps.exif_transpose(img)
    report.width, report.height = oriented.size
    if max(oriented.size) < s.min_long_edge_px:
        report.codes.append("resolution_too_low")

    gray = _analysis_gray(oriented)
    report.sharpness = round(tile_sharpness(gray), 2)
    report.highlight_clip = round(float(np.mean(gray >= 251)), 4)
    report.shadow_clip = round(float(np.mean(gray <= 4)), 4)

    if report.sharpness < s.min_sharpness:
        report.codes.append("too_blurry")
    if report.highlight_clip > s.max_highlight_clip:
        report.codes.append("overexposed")
    if report.shadow_clip > s.max_shadow_clip:
        report.codes.append("underexposed")

    report.passed = not report.codes
    return report, img
