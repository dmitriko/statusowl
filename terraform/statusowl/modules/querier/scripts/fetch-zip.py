#!/usr/bin/env python3
"""External Terraform data source: fetch the querier zip and (optionally) verify its SHA-256.

Reads JSON on stdin: {"url": ..., "expected_sha": ..., "output_path": ...}.
Writes JSON on stdout:  {"path": ..., "sha256_hex": ..., "sha256_b64": ...}.
On SHA-256 mismatch: writes a diagnostic to stderr and exits non-zero — Terraform
surfaces this as a plan-time error so a tampered or wrong-version artifact never
makes it into source_code_hash.
"""

from __future__ import annotations

import base64
import hashlib
import json
import os
import sys
import urllib.request


def main() -> int:
    inp = json.load(sys.stdin)
    url: str = inp["url"]
    expected: str = inp.get("expected_sha", "") or ""
    out: str = inp["output_path"]

    os.makedirs(os.path.dirname(out), exist_ok=True)

    req = urllib.request.Request(url, headers={"User-Agent": "statusowl-terraform"})
    with urllib.request.urlopen(req) as resp, open(out, "wb") as f:
        while True:
            chunk = resp.read(64 * 1024)
            if not chunk:
                break
            f.write(chunk)

    with open(out, "rb") as f:
        digest = hashlib.sha256(f.read()).digest()
    sha_hex = digest.hex()
    sha_b64 = base64.b64encode(digest).decode()

    if expected and expected.lower() != sha_hex:
        print(
            f"sha256 mismatch for {url}: expected {expected}, got {sha_hex}",
            file=sys.stderr,
        )
        return 1

    json.dump({"path": out, "sha256_hex": sha_hex, "sha256_b64": sha_b64}, sys.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())
