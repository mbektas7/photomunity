import asyncio

from alembic import context
from sqlalchemy.ext.asyncio import create_async_engine

from app import models  # noqa: F401  modelleri kaydet
from app.core.config import get_settings
from app.core.database import Base

target_metadata = Base.metadata


def include_object(obj, name, type_, reflected, compare_to):
    # postgis/postgis imajı veritabanına PostGIS, topology ve tiger geocoder tablolarını kurar
    # (spatial_ref_sys, topology, addr, ...). Bunlar modellerimizde olmadığı için autogenerate
    # onları DROP etmeye çalışır; yalnızca modellerimizde tanımlı tabloları karşılaştır.
    if type_ == "table" and reflected and compare_to is None:
        return False
    return True


def run_offline():
    context.configure(
        url=get_settings().database_url, target_metadata=target_metadata, literal_binds=True, include_object=include_object
    )
    with context.begin_transaction():
        context.run_migrations()


def _run(connection):
    context.configure(
        connection=connection, target_metadata=target_metadata, compare_type=True, include_object=include_object
    )
    with context.begin_transaction():
        context.run_migrations()


async def run_online():
    engine = create_async_engine(get_settings().database_url)
    async with engine.connect() as conn:
        await conn.run_sync(_run)
    await engine.dispose()


if context.is_offline_mode():
    run_offline()
else:
    asyncio.run(run_online())
