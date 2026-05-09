import json

from querier import handler

from .conftest import BUCKET


def test_happy_path_runs_and_audits(aws):
    resp = handler.lambda_handler({"code": "print('ok')", "timeout_seconds": 5}, None)
    assert resp["ok"] is True
    assert resp["stdout"].strip() == "ok"
    assert resp["exit_code"] == 0
    assert resp["audit_id"]

    obj = aws.get_object(Bucket=BUCKET, Key=resp["audit_key"])
    record = json.loads(obj["Body"].read())
    assert record["code"] == "print('ok')"
    assert record["stdout"].strip() == "ok"
    assert record["args"]["timeout_seconds"] == 5
    assert record["caller_identity"]["account"]


def test_audit_key_uses_dated_path(aws):
    resp = handler.lambda_handler({"code": "print(1)"}, None)
    assert resp["audit_key"].startswith("audit/")
    assert resp["audit_key"].endswith(".json")
    # audit/YYYY/MM/DD/{uuid}.json
    parts = resp["audit_key"].split("/")
    assert len(parts) == 5
    assert len(parts[1]) == 4 and parts[1].isdigit()


def test_invalid_event_audited_and_rejected(aws):
    resp = handler.lambda_handler({"code": ""}, None)
    assert resp["ok"] is False
    assert "non-empty" in resp["error"]
    assert resp["audit_id"]


def test_non_dict_event_rejected(aws):
    resp = handler.lambda_handler("not an event", None)
    assert resp["ok"] is False
    assert "JSON object" in resp["error"]


def test_timeout_recorded_in_audit(aws):
    resp = handler.lambda_handler(
        {"code": "import time; time.sleep(10)", "timeout_seconds": 1},
        None,
    )
    assert resp["timed_out"] is True
    assert resp["ok"] is False

    record = json.loads(aws.get_object(Bucket=BUCKET, Key=resp["audit_key"])["Body"].read())
    assert record["timed_out"] is True
    assert "timeout" in record["stderr"].lower()


def test_default_timeout_used_when_omitted(aws):
    resp = handler.lambda_handler({"code": "print('x')"}, None)
    assert resp["ok"] is True
    record = json.loads(aws.get_object(Bucket=BUCKET, Key=resp["audit_key"])["Body"].read())
    assert record["args"]["timeout_seconds"] == 30  # DEFAULT_TIMEOUT_S default
