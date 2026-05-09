"""Account configuration & cross-account session resolution.

v0 stub: account map is loaded from `ACCOUNTS_CONFIG` (a JSON string of
`{name: role_arn}`). A later pass will swap this for accounts.yaml in
S3 / SSM, but the call shape stays the same.
"""

from __future__ import annotations

import json

import boto3

from . import config


def load_accounts() -> dict[str, str]:
    raw = config.accounts_config()
    if not raw:
        return {}
    return json.loads(raw)


def get_session(account: str | None) -> boto3.Session:
    """Return a boto3.Session for the requested account.

    None → the Lambda's own execution role.
    Otherwise → assume the role mapped to `account` in ACCOUNTS_CONFIG.
    """
    if account is None:
        return boto3.Session()

    role_arn = load_accounts().get(account)
    if not role_arn:
        raise ValueError(f"unknown account: {account!r}")

    resp = boto3.client("sts").assume_role(
        RoleArn=role_arn,
        RoleSessionName=f"statusowl-querier-{account}",
        DurationSeconds=900,
    )
    creds = resp["Credentials"]
    return boto3.Session(
        aws_access_key_id=creds["AccessKeyId"],
        aws_secret_access_key=creds["SecretAccessKey"],
        aws_session_token=creds["SessionToken"],
    )


def session_to_env(session: boto3.Session) -> dict[str, str]:
    """Materialize session creds as AWS_* env vars for the subprocess.

    Generated code uses these; we don't pickle the boto3 session across
    the process boundary.
    """
    creds = session.get_credentials()
    if creds is None:
        return {}
    frozen = creds.get_frozen_credentials()
    env = {
        "AWS_ACCESS_KEY_ID": frozen.access_key,
        "AWS_SECRET_ACCESS_KEY": frozen.secret_key,
    }
    if frozen.token:
        env["AWS_SESSION_TOKEN"] = frozen.token
    if session.region_name:
        env["AWS_REGION"] = session.region_name
        env["AWS_DEFAULT_REGION"] = session.region_name
    return env
