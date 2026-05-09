"""Run the querier handler locally with a moto-mocked S3 audit bucket.

    cat event.json | uv run python scripts/invoke_local.py
    uv run python scripts/invoke_local.py --event scripts/sample_event.json
"""

from __future__ import annotations

import argparse
import json
import os
import sys

import boto3
from moto import mock_aws

DEFAULT_BUCKET = "statusowl-local-audit"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--event", help="Path to JSON event file (default: stdin)")
    parser.add_argument("--bucket", default=DEFAULT_BUCKET)
    args = parser.parse_args()

    if args.event:
        with open(args.event) as f:
            event = json.load(f)
    else:
        event = json.load(sys.stdin)

    os.environ.setdefault("AWS_ACCESS_KEY_ID", "testing")
    os.environ.setdefault("AWS_SECRET_ACCESS_KEY", "testing")
    os.environ.setdefault("AWS_DEFAULT_REGION", "us-east-1")
    os.environ["AUDIT_BUCKET"] = args.bucket

    with mock_aws():
        s3 = boto3.client("s3", region_name="us-east-1")
        s3.create_bucket(Bucket=args.bucket)

        from querier import handler
        result = handler.lambda_handler(event, None)
        print(json.dumps(result, indent=2, default=str))

        listing = s3.list_objects_v2(Bucket=args.bucket).get("Contents", [])
        print(f"\n--- audit bucket: {args.bucket} ---", file=sys.stderr)
        for obj in listing:
            print(obj["Key"], file=sys.stderr)

    return 0


if __name__ == "__main__":
    sys.exit(main())
