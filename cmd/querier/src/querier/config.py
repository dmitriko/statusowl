"""Env-var accessors for the querier Lambda.

Functions (not module-level constants) so tests can monkeypatch the
environment without reload juggling.
"""

from __future__ import annotations

import os


def audit_bucket() -> str:
    return os.environ.get("AUDIT_BUCKET", "")


def accounts_config() -> str:
    return os.environ.get("ACCOUNTS_CONFIG", "")


def max_timeout_s() -> int:
    return int(os.environ.get("MAX_TIMEOUT_S", "60"))


def default_timeout_s() -> int:
    return int(os.environ.get("DEFAULT_TIMEOUT_S", "30"))


def mem_limit_mb() -> int | None:
    raw = os.environ.get("MEM_LIMIT_MB", "")
    return int(raw) if raw else None
