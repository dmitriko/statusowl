"""Lambda entry point: validate event, run code, write audit record."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime
from typing import Any

from . import accounts, audit, config, executor, identity


class InvalidEvent(ValueError):
    pass


def _validate(event: Any) -> tuple[str, int, str | None]:
    if not isinstance(event, dict):
        raise InvalidEvent("event must be a JSON object")
    code = event.get("code")
    if not isinstance(code, str) or not code.strip():
        raise InvalidEvent("`code` must be a non-empty string")
    timeout = event.get("timeout_seconds", config.default_timeout_s())
    if not isinstance(timeout, int) or isinstance(timeout, bool) or timeout <= 0:
        raise InvalidEvent("`timeout_seconds` must be a positive int")
    account = event.get("account")
    if account is not None and not isinstance(account, str):
        raise InvalidEvent("`account` must be a string when present")
    return code, timeout, account


def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    record_id = str(uuid.uuid4())
    started = datetime.now(UTC)

    try:
        code, timeout, account = _validate(event)
    except InvalidEvent as exc:
        # Audit malformed events too — probing attempts should be visible.
        audit.write({
            "id": record_id,
            "timestamp": started.isoformat(),
            "error": str(exc),
            "event": event,
        })
        return {"ok": False, "error": str(exc), "audit_id": record_id}

    session = accounts.get_session(account)
    extra_env = accounts.session_to_env(session)
    result = executor.run_code(code, timeout, extra_env=extra_env)

    record = {
        "id": record_id,
        "timestamp": started.isoformat(),
        "account": account,
        "caller_identity": identity.caller_identity(),
        "code": code,
        "args": {"timeout_seconds": timeout, "account": account},
        "stdout": result.stdout,
        "stderr": result.stderr,
        "exit_code": result.exit_code,
        "duration_ms": result.duration_ms,
        "timed_out": result.timed_out,
        "truncated": result.truncated,
    }
    audit_key = audit.write(record)

    return {
        "ok": result.exit_code == 0,
        "stdout": result.stdout,
        "stderr": result.stderr,
        "exit_code": result.exit_code,
        "duration_ms": result.duration_ms,
        "timed_out": result.timed_out,
        "truncated": result.truncated,
        "audit_id": record_id,
        "audit_key": audit_key,
    }
