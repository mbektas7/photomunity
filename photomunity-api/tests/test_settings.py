import pytest

from app.core.config import Settings

GOOD = dict(
    environment="production",
    jwt_secret="x" * 64,
    frontend_url="https://photomunity.com",
    cors_origins=["https://photomunity.com"],
    s3_access_key="AKIA",
    s3_secret_key="secret",
    cdn_base_url="https://cdn.photomunity.com",
)


def test_production_accepts_real_settings():
    Settings(_env_file=None, **GOOD)


@pytest.mark.parametrize("field,value", [
    ("jwt_secret", "change-me-in-production"),
    ("jwt_secret", "short"),
    ("cors_origins", ["http://localhost:3000"]),
    ("s3_access_key", "minioadmin"),
    ("cdn_base_url", ""),
])
def test_production_rejects_dev_defaults(field, value):
    with pytest.raises(ValueError):
        Settings(_env_file=None, **{**GOOD, field: value})


def test_development_keeps_defaults():
    Settings(_env_file=None, environment="development")


def test_presigned_upload_uses_public_endpoint(monkeypatch):
    from app.services import storage

    s = Settings(_env_file=None, s3_endpoint_url="http://minio:9000",
                 s3_public_endpoint_url="https://media.example.com", s3_bucket="b")
    monkeypatch.setattr(storage, "get_settings", lambda: s)
    storage._client.cache_clear()
    try:
        post = storage.presigned_upload("originals/x.jpg", "image/jpeg", 100)
        assert post["url"].startswith("https://media.example.com")
        assert storage._client().meta.endpoint_url == "http://minio:9000"
    finally:
        storage._client.cache_clear()
