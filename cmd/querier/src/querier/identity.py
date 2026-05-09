"""Caller identity lookup, used to stamp audit records."""

from __future__ import annotations

import boto3


def caller_identity() -> dict[str, str]:
    resp = boto3.client("sts").get_caller_identity()
    return {
        "account": resp.get("Account", ""),
        "arn": resp.get("Arn", ""),
        "user_id": resp.get("UserId", ""),
    }
