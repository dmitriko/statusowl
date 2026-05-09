"""S3 audit log writer. Every querier invocation produces one record."""

from __future__ import annotations

import json
from datetime import UTC, datetime
from typing import Any

import boto3

from . import config


def s3_key(record_id: str, when: datetime | None = None) -> str:
    when = when or datetime.now(UTC)
    return f"audit/{when:%Y/%m/%d}/{record_id}.json"


def write(record: dict[str, Any]) -> str:
    bucket_name = config.bucket()
    if not bucket_name:
        raise RuntimeError("STATUSOWL_BUCKET env var is not set")

    key = s3_key(record["id"])
    boto3.client("s3").put_object(
        Bucket=bucket_name,
        Key=key,
        Body=json.dumps(record, default=str).encode("utf-8"),
        ContentType="application/json",
    )
    return key
