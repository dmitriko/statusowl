import json
from datetime import UTC, datetime

import pytest

from querier import audit

from .conftest import AUDIT_BUCKET


def test_s3_key_format():
    when = datetime(2026, 5, 9, 12, 0, tzinfo=UTC)
    assert audit.s3_key("abc-123", when=when) == "audit/2026/05/09/abc-123.json"


def test_write_puts_record_to_s3(aws):
    record = {"id": "00000000-0000-0000-0000-000000000001", "code": "print(1)"}
    key = audit.write(record)
    body = json.loads(aws.get_object(Bucket=AUDIT_BUCKET, Key=key)["Body"].read())
    assert body == record


def test_write_without_bucket_env_raises(monkeypatch):
    monkeypatch.delenv("AUDIT_BUCKET", raising=False)
    with pytest.raises(RuntimeError, match="AUDIT_BUCKET"):
        audit.write({"id": "x"})
