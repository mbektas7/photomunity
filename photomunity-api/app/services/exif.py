"""EXIF çıkarımı. GPS ayrı tutulur ve hiçbir zaman kamuya açık türevlere yazılmaz."""
from datetime import datetime
from fractions import Fraction

from PIL import ExifTags, Image, TiffImagePlugin

_SKIP_RAW = {"MakerNote", "UserComment", "PrintImageMatching", "ComponentsConfiguration"}


def _num(v) -> float | None:
    try:
        return float(v) if v is not None else None
    except (TypeError, ValueError, ZeroDivisionError):
        return None


def _str(v) -> str | None:
    if v is None:
        return None
    if isinstance(v, bytes):
        v = v.decode("utf-8", "ignore")
    v = str(v).replace("\x00", "").strip()
    return v or None


def _json_safe(v):
    if isinstance(v, TiffImagePlugin.IFDRational):
        return _num(v)
    if isinstance(v, (str, int, float, bool)) or v is None:
        return v.replace("\x00", "").strip() if isinstance(v, str) else v
    if isinstance(v, (tuple, list)):
        return [_json_safe(x) for x in v]
    if isinstance(v, bytes):
        return None
    return str(v)


def _parse_dt(v) -> datetime | None:
    v = _str(v)
    if not v:
        return None
    for fmt in ("%Y:%m:%d %H:%M:%S", "%Y-%m-%d %H:%M:%S", "%Y-%m-%dT%H:%M:%S"):
        try:
            return datetime.strptime(v[:19], fmt)
        except ValueError:
            continue
    return None


def shutter_display(exposure: float | None) -> str | None:
    if not exposure or exposure <= 0:
        return None
    if exposure >= 1:
        return f'{exposure:g}"'
    return f"1/{round(1 / exposure)}"


def _dms_to_deg(dms, ref) -> float | None:
    try:
        d, m, s = (float(x) for x in dms)
    except (TypeError, ValueError, ZeroDivisionError):
        return None
    deg = d + m / 60 + s / 3600
    return -deg if _str(ref) in ("S", "W") else deg


def extract_exif(img: Image.Image) -> dict:
    exif = img.getexif()
    if not exif:
        return {"raw": {}}

    tags = {ExifTags.TAGS.get(k, str(k)): v for k, v in exif.items()}
    tags.update({ExifTags.TAGS.get(k, str(k)): v for k, v in exif.get_ifd(ExifTags.IFD.Exif).items()})
    gps = {ExifTags.GPSTAGS.get(k, str(k)): v for k, v in exif.get_ifd(ExifTags.IFD.GPSInfo).items()}

    iso = tags.get("ISOSpeedRatings") or tags.get("PhotographicSensitivity")
    if isinstance(iso, (tuple, list)):
        iso = iso[0] if iso else None
    exposure = _num(tags.get("ExposureTime"))
    flash = tags.get("Flash")
    wb = tags.get("WhiteBalance")
    f35 = tags.get("FocalLengthIn35mmFilm")

    lat = lng = None
    if "GPSLatitude" in gps and "GPSLongitude" in gps:
        lat = _dms_to_deg(gps["GPSLatitude"], gps.get("GPSLatitudeRef"))
        lng = _dms_to_deg(gps["GPSLongitude"], gps.get("GPSLongitudeRef"))

    raw = {k: _json_safe(v) for k, v in tags.items() if k not in _SKIP_RAW and not k.startswith("GPS")}
    raw = {k: v for k, v in raw.items() if v is not None and k not in ("ExifOffset", "GPSInfo")}

    return {
        "camera_make": _str(tags.get("Make")),
        "camera_model": _str(tags.get("Model")),
        "lens": _str(tags.get("LensModel")),
        "focal_length_mm": _num(tags.get("FocalLength")),
        "focal_length_35mm": int(f35) if f35 else None,
        "aperture": _num(tags.get("FNumber")),
        "exposure_time": exposure,
        "shutter_display": shutter_display(exposure),
        "iso": int(iso) if iso else None,
        "taken_at": _parse_dt(tags.get("DateTimeOriginal") or tags.get("DateTime")),
        "white_balance": {0: "auto", 1: "manual"}.get(wb) if wb is not None else None,
        "flash_fired": bool(int(flash) & 1) if flash is not None else None,
        "gps_latitude": lat,
        "gps_longitude": lng,
        "raw": raw,
    }
