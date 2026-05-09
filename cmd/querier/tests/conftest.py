import boto3
import pytest
from moto import mock_aws

AUDIT_BUCKET = "statusowl-test-audit"


@pytest.fixture(autouse=True)
def _aws_creds(monkeypatch):
    monkeypatch.setenv("AWS_ACCESS_KEY_ID", "testing")
    monkeypatch.setenv("AWS_SECRET_ACCESS_KEY", "testing")
    monkeypatch.setenv("AWS_SESSION_TOKEN", "testing")
    monkeypatch.setenv("AWS_DEFAULT_REGION", "us-east-1")


@pytest.fixture
def aws(monkeypatch):
    monkeypatch.setenv("AUDIT_BUCKET", AUDIT_BUCKET)
    with mock_aws():
        s3 = boto3.client("s3", region_name="us-east-1")
        s3.create_bucket(Bucket=AUDIT_BUCKET)
        yield s3
