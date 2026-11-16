import io
import os
import tempfile

_db = os.path.join(tempfile.mkdtemp(), "test.db")
os.environ["ENVIRONMENT"] = "test"
os.environ["DATABASE_URL"] = f"sqlite+aiosqlite:///{_db}"
os.environ["S3_ENDPOINT_URL"] = "http://localhost:9000"
os.environ["RATE_LIMIT_ENABLED"] = "false"

import numpy as np  # noqa: E402
import pytest  # noqa: E402
import pytest_asyncio  # noqa: E402
from httpx import ASGITransport, AsyncClient  # noqa: E402
from PIL import Image  # noqa: E402

from app.core.database import Base, engine  # noqa: E402
from app.main import app  # noqa: E402
from app.services import storage  # noqa: E402


@pytest.fixture
def fake_storage(monkeypatch):
    store: dict[str, bytes] = {}
    monkeypatch.setattr(storage, "get_object", lambda key: store[key])
    monkeypatch.setattr(storage, "put_object", lambda key, data, ct: store.__setitem__(key, data))
    monkeypatch.setattr(storage, "delete_objects", lambda keys: [store.pop(k, None) for k in keys])
    return store


@pytest_asyncio.fixture
async def client():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test/api/v1") as c:
        yield c


def make_jpeg(w=3000, h=2000, blur=False, fill=None, exif=None, seed=1) -> bytes:
    rng = np.random.default_rng(seed)
    if fill is not None:
        arr = np.full((h, w, 3), fill, dtype=np.uint8)
    else:
        arr = rng.integers(30, 225, (h, w, 3), dtype=np.uint8)
    img = Image.fromarray(arr)
    if blur:
        from PIL import ImageFilter
        img = img.filter(ImageFilter.GaussianBlur(25))
    buf = io.BytesIO()
    img.save(buf, "JPEG", quality=95, exif=exif or Image.Exif())
    return buf.getvalue()
