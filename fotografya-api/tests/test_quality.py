from PIL import ExifTags, Image

from app.core.config import get_settings
from app.services.exif import extract_exif, shutter_display
from app.services.quality import analyze_image
from tests.conftest import make_jpeg

S = get_settings()


def test_sharp_image_passes():
    report, img = analyze_image(make_jpeg(), S)
    assert report.passed, report
    assert img is not None and report.width == 3000


def test_blurry_image_rejected():
    report, _ = analyze_image(make_jpeg(blur=True), S)
    assert "too_blurry" in report.codes


def test_small_resolution_rejected():
    report, _ = analyze_image(make_jpeg(1200, 800), S)
    assert "resolution_too_low" in report.codes


def test_overexposed_and_underexposed():
    assert "overexposed" in analyze_image(make_jpeg(fill=255), S)[0].codes
    assert "underexposed" in analyze_image(make_jpeg(fill=0), S)[0].codes


def test_garbage_rejected():
    report, img = analyze_image(b"x" * 2_000_000, S)
    assert report.codes == ["corrupt_image"] and img is None


def test_exif_extraction_and_gps():
    exif = Image.Exif()
    exif[ExifTags.Base.Make] = "Sony"
    exif[ExifTags.Base.Model] = "ILCE-7M4"
    sub = {}
    sub[ExifTags.Base.FNumber] = 2.8
    sub[ExifTags.Base.ExposureTime] = 1 / 250
    sub[ExifTags.Base.ISOSpeedRatings] = 400
    sub[ExifTags.Base.FocalLength] = 35.0
    sub[ExifTags.Base.LensModel] = "FE 35mm F1.8"
    sub[ExifTags.Base.DateTimeOriginal] = "2026:08:12 22:41:05"
    gps = {}
    gps[ExifTags.GPS.GPSLatitudeRef] = "N"
    gps[ExifTags.GPS.GPSLatitude] = (41.0, 0.0, 18.0)
    gps[ExifTags.GPS.GPSLongitudeRef] = "E"
    gps[ExifTags.GPS.GPSLongitude] = (39.0, 43.0, 12.0)
    exif[ExifTags.IFD.Exif] = sub
    exif[ExifTags.IFD.GPSInfo] = gps

    _, img = analyze_image(make_jpeg(exif=exif), S)
    data = extract_exif(img)
    assert data["camera_make"] == "Sony" and data["camera_model"] == "ILCE-7M4"
    assert data["aperture"] == 2.8 and data["iso"] == 400
    assert data["shutter_display"] == "1/250"
    assert data["lens"] == "FE 35mm F1.8"
    assert data["taken_at"].year == 2026
    assert round(data["gps_latitude"], 3) == 41.005 and round(data["gps_longitude"], 2) == 39.72


def test_shutter_display():
    assert shutter_display(1 / 4000) == "1/4000"
    assert shutter_display(20.0) == '20"'
