"""S3 uyumlu depolama. Orijinaller originals/ altında özel kalır; CDN yalnızca photos/ önekini yayınlar."""
from functools import lru_cache

import boto3
from botocore.config import Config

from app.core.config import get_settings


@lru_cache
def _client():
    s = get_settings()
    return boto3.client(
        "s3",
        endpoint_url=s.s3_endpoint_url,
        region_name=s.s3_region,
        aws_access_key_id=s.s3_access_key or "dev",
        aws_secret_access_key=s.s3_secret_key or "dev",
        config=Config(signature_version="s3v4"),
    )


def presigned_upload(key: str, content_type: str, max_bytes: int) -> dict:
    """İstemcinin doğrudan depolamaya yüklemesi için multipart POST imzası (boyut sınırı sunucu tarafında zorlanır)."""
    s = get_settings()
    return _client().generate_presigned_post(
        Bucket=s.s3_bucket,
        Key=key,
        Fields={"Content-Type": content_type},
        Conditions=[{"Content-Type": content_type}, ["content-length-range", 1, max_bytes]],
        ExpiresIn=s.upload_url_ttl_seconds,
    )


def get_object(key: str) -> bytes:
    return _client().get_object(Bucket=get_settings().s3_bucket, Key=key)["Body"].read()


def put_object(key: str, data: bytes, content_type: str) -> None:
    _client().put_object(
        Bucket=get_settings().s3_bucket, Key=key, Body=data, ContentType=content_type,
        CacheControl="public, max-age=31536000, immutable",
    )


def delete_objects(keys: list[str]) -> None:
    keys = [k for k in keys if k]
    for i in range(0, len(keys), 1000):
        _client().delete_objects(
            Bucket=get_settings().s3_bucket,
            Delete={"Objects": [{"Key": k} for k in keys[i : i + 1000]], "Quiet": True},
        )


def public_url(key: str) -> str:
    s = get_settings()
    if s.cdn_base_url:
        return f"{s.cdn_base_url.rstrip('/')}/{key}"
    endpoint = (s.s3_endpoint_url or f"https://{s.s3_bucket}.s3.amazonaws.com").rstrip("/")
    return f"{endpoint}/{s.s3_bucket}/{key}" if s.s3_endpoint_url else f"{endpoint}/{key}"
