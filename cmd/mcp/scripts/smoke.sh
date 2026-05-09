#!/usr/bin/env bash
# Smoke test: launch the binary, complete the MCP initialize handshake,
# request tools/list, and assert that run_python is advertised.

set -euo pipefail

BIN="${1:-./dist/statusowl-mcp}"

if [[ ! -x "$BIN" ]]; then
  echo "smoke: binary not found or not executable: $BIN" >&2
  exit 2
fi

# A dummy function name is fine — tools/list doesn't invoke the querier.
# AWS creds aren't even loaded until the first invoke.
#
# The trailing sleep keeps the stdin pipe open just long enough for the
# server to flush responses to stdout before it sees EOF and exits. Without
# it the server can shut down before we've read its tools/list reply.
out=$(
  {
    cat <<'EOF'
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"smoke","version":"0"}}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":2,"method":"tools/list"}
EOF
    sleep 0.5
  } | STATUSOWL_QUERIER_FUNCTION_NAME=dummy "$BIN" 2>/dev/null
)

if echo "$out" | grep -q '"name":"run_python"'; then
  echo "smoke: PASS (run_python advertised)"
  exit 0
fi

echo "smoke: FAIL — run_python not in tools/list response" >&2
echo "--- server output ---" >&2
echo "$out" >&2
exit 1
