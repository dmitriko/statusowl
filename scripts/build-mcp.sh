#!/usr/bin/env bash
# Builds MCP server artifacts. Single source of truth for `make build-mcp`
# and the GitHub release workflow — they invoke this script unchanged so
# what CI ships matches what `make` produces.
#
# Modes (KIND env var):
#   dev     (default) Native binary at cmd/mcp/dist/statusowl-mcp.
#   binary  Release-naming binary at cmd/mcp/dist/statusowl-mcp_<os>_<arch>[.exe].
#   lambda  Deterministic Lambda zip at cmd/mcp/dist/statusowl-mcp_lambda_<arch>.zip
#           containing a single `bootstrap` binary built for linux/<arch>.
#
# Reproducibility: -trimpath, -ldflags="-s -w -buildid=", CGO_ENABLED=0,
# zip mtime fixed to the HEAD commit (override with SOURCE_DATE_EPOCH).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MCP_DIR="${REPO_ROOT}/cmd/mcp"
DIST_DIR="${MCP_DIR}/dist"

KIND="${KIND:-dev}"

case "$KIND" in
  dev)
    GOOS="${GOOS:-$(go env GOOS)}"
    GOARCH="${GOARCH:-$(go env GOARCH)}"
    binname="statusowl-mcp"
    [[ "$GOOS" == "windows" ]] && binname="statusowl-mcp.exe"
    out_path="${DIST_DIR}/${binname}"
    ;;
  binary)
    : "${GOOS:?KIND=binary requires GOOS}"
    : "${GOARCH:?KIND=binary requires GOARCH}"
    suffix="${GOOS}_${GOARCH}"
    [[ "$GOOS" == "windows" ]] && suffix="${suffix}.exe"
    out_path="${DIST_DIR}/statusowl-mcp_${suffix}"
    ;;
  lambda)
    : "${GOARCH:?KIND=lambda requires GOARCH}"
    GOOS=linux
    out_path="${DIST_DIR}/statusowl-mcp_lambda_${GOARCH}.zip"
    ;;
  *)
    echo "build-mcp: unknown KIND=$KIND (dev|binary|lambda)" >&2
    exit 1
    ;;
esac

# Source date epoch for zip mtimes.
if [[ -n "${SOURCE_DATE_EPOCH:-}" ]]; then
  epoch="${SOURCE_DATE_EPOCH}"
elif git -C "${REPO_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  epoch="$(git -C "${REPO_ROOT}" log -1 --format=%ct)"
else
  epoch=315532800
fi

mkdir -p "${DIST_DIR}"
rm -f "${out_path}" "${out_path}.sha256"

# Build the Go binary into a temp path, then either move it to its final
# location (binary/dev) or pack it into a deterministic zip (lambda).
tmp_bin="$(mktemp)"
trap 'rm -f "$tmp_bin"' EXIT

(
  cd "${MCP_DIR}"
  CGO_ENABLED=0 GOOS="$GOOS" GOARCH="$GOARCH" \
    go build \
      -trimpath \
      -ldflags="-s -w -buildid=" \
      -o "${tmp_bin}" \
      ./...
)

if [[ "$KIND" == "lambda" ]]; then
  python3 - "$tmp_bin" "$out_path" "$epoch" <<'PY'
import os, sys, time, zipfile

src, out, epoch = sys.argv[1], sys.argv[2], int(sys.argv[3])
date_time = time.gmtime(epoch)[:6]

with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    zi = zipfile.ZipInfo(filename="bootstrap", date_time=date_time)
    # Regular file (S_IFREG) with 0755 perms — Lambda needs the bootstrap
    # binary executable.
    zi.external_attr = (0o100755) << 16
    zi.create_system = 3
    zi.compress_type = zipfile.ZIP_DEFLATED
    with open(src, "rb") as fh:
        z.writestr(zi, fh.read())
print(f"wrote {out} (mtime epoch={epoch})", file=sys.stderr)
PY
else
  cp "${tmp_bin}" "${out_path}"
  chmod +x "${out_path}"
fi

# SHA-256 sidecar (skip for dev mode — it's a working file, not a release).
if [[ "$KIND" != "dev" ]]; then
  if command -v sha256sum >/dev/null 2>&1; then
    sha_cmd=(sha256sum)
  else
    sha_cmd=(shasum -a 256)
  fi
  ( cd "$(dirname "${out_path}")" && "${sha_cmd[@]}" "$(basename "${out_path}")" > "$(basename "${out_path}").sha256" )
  echo "==> ${out_path}"
  cat "${out_path}.sha256"
else
  echo "==> ${out_path}"
fi
