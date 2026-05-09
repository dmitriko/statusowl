import json

import boto3
import pytest

from querier import accounts


def test_no_account_returns_default_session():
    session = accounts.get_session(None)
    assert session.get_credentials() is not None


def test_unknown_account_raises(monkeypatch):
    monkeypatch.setenv("ACCOUNTS_CONFIG", json.dumps({}))
    with pytest.raises(ValueError, match="unknown account"):
        accounts.get_session("nope")


def test_session_to_env_includes_creds(monkeypatch):
    monkeypatch.setenv("AWS_ACCESS_KEY_ID", "AKIATEST")
    monkeypatch.setenv("AWS_SECRET_ACCESS_KEY", "secret")
    monkeypatch.setenv("AWS_SESSION_TOKEN", "tok")
    monkeypatch.setenv("AWS_DEFAULT_REGION", "us-east-1")
    env = accounts.session_to_env(boto3.Session())
    assert env["AWS_ACCESS_KEY_ID"] == "AKIATEST"
    assert env["AWS_SECRET_ACCESS_KEY"] == "secret"
    assert env["AWS_SESSION_TOKEN"] == "tok"
    assert env["AWS_REGION"] == "us-east-1"
