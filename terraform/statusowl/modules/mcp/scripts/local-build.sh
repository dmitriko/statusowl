#!/usr/bin/env bash
# Terraform external data source: invoke scripts/build-mcp.sh and report
# the resulting Lambda zip's path + base64 SHA-256 back to Terraform.
#
# This is the "no zip URL, no zip path" fallback — only fires when neither
# function_zip_url nor function_zip_path is set on the module. It runs
# `go build` on every plan, which is fine for development and not great for
# anything else. Pin a release URL in production.

set -euo pipefail

# Read the JSON query from stdin (Terraform external data source contract).
input="$(cat)"

# Use python3 (already required by the rest of the build) to parse stdin and
# emit JSON — saves a jq dependency.
py() { python3 -c "$@"; }

repo_root="$(py "import json,sys; print(json.loads('''$input''')['repo_root'])")"
arch="$(py "import json,sys; print(json.loads('''$input''')['arch'])")"

repo_root_abs="$(cd "$repo_root" && pwd)"

KIND=lambda GOARCH="$arch" "${repo_root_abs}/scripts/build-mcp.sh" >&2

zip_path="${repo_root_abs}/cmd/mcp/dist/statusowl-mcp_lambda_${arch}.zip"

if [[ ! -f "$zip_path" ]]; then
  echo "local-build: expected zip not found at $zip_path" >&2
  exit 1
fi

# Emit JSON: { path, sha256_hex, sha256_b64 }.
python3 - "$zip_path" <<'PY'
import base64, hashlib, json, sys
path = sys.argv[1]
with open(path, "rb") as f:
    digest = hashlib.sha256(f.read()).digest()
json.dump({
    "path": path,
    "sha256_hex": digest.hex(),
    "sha256_b64": base64.b64encode(digest).decode(),
}, sys.stdout)
PY
