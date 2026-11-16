import pytest

from app.core.config import Settings

GOOD = dict(
    environment="production",
    jwt_secret="x" * 64,
    frontend_url="https://photomunity.app",
    cors_origins=["https://photomunity.app"],
    s3_access_key="AKIA",
    s3_secret_key="secret",
    cdn_base_url="https://cdn.photomunity.app",
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
