#!/usr/bin/env bash
# Builds a deterministic zip of the querier Lambda at cmd/querier/build/querier.zip
# plus a sidecar querier.zip.sha256.
#
# Reproducibility: sorted file order, fixed mtime taken from the HEAD commit
# (override with SOURCE_DATE_EPOCH). Excludes __pycache__, .pytest_cache, *.pyc.
#
# Single source of truth for both `make build-querier` and the GitHub release
# workflow — they invoke this script unchanged so artifacts are bit-identical.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SRC_PARENT="${REPO_ROOT}/cmd/querier/src"
BUILD_DIR="${REPO_ROOT}/cmd/querier/build"
OUT_ZIP="${BUILD_DIR}/querier.zip"

if [[ ! -d "${SRC_PARENT}/querier" ]]; then
  echo "querier source not found at ${SRC_PARENT}/querier" >&2
  exit 1
fi

# Pin a timestamp for reproducibility.
if [[ -n "${SOURCE_DATE_EPOCH:-}" ]]; then
  epoch="${SOURCE_DATE_EPOCH}"
elif git -C "${REPO_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  epoch="$(git -C "${REPO_ROOT}" log -1 --format=%ct)"
else
  echo "not in a git repo and SOURCE_DATE_EPOCH not set; using a fixed epoch for determinism" >&2
  epoch=315532800   # 1980-01-01, the earliest zip-format mtime
fi

mkdir -p "${BUILD_DIR}"
rm -f "${OUT_ZIP}" "${OUT_ZIP}.sha256"

python3 - "${SRC_PARENT}" "${OUT_ZIP}" "${epoch}" <<'PY'
import os
import sys
import time
import zipfile

src_parent, out_path, epoch = sys.argv[1], sys.argv[2], int(sys.argv[3])
date_time = time.gmtime(epoch)[:6]

EXCLUDE_DIRS = {"__pycache__", ".pytest_cache", ".ruff_cache"}
EXCLUDE_SUFFIXES = (".pyc",)

paths: list[tuple[str, str]] = []
for root, dirs, files in os.walk(os.path.join(src_parent, "querier")):
    dirs[:] = sorted(d for d in dirs if d not in EXCLUDE_DIRS)
    for name in sorted(files):
        if name.endswith(EXCLUDE_SUFFIXES):
            continue
        full = os.path.join(root, name)
        arc = os.path.relpath(full, src_parent)
        paths.append((arc, full))
paths.sort(key=lambda p: p[0])

with zipfile.ZipFile(out_path, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for arc, full in paths:
        zi = zipfile.ZipInfo(filename=arc, date_time=date_time)
        # Regular file (S_IFREG) with 0644 perms in the high 16 bits.
        zi.external_attr = (0o100644) << 16
        zi.create_system = 3   # Unix; avoids host-specific value
        zi.compress_type = zipfile.ZIP_DEFLATED
        with open(full, "rb") as fh:
            z.writestr(zi, fh.read())

print(f"wrote {out_path} ({len(paths)} files, mtime epoch={epoch})", file=sys.stderr)
PY

# Sidecar checksum.
if command -v sha256sum >/dev/null 2>&1; then
  sha256_cmd=(sha256sum)
else
  sha256_cmd=(shasum -a 256)
fi

(cd "${BUILD_DIR}" && "${sha256_cmd[@]}" querier.zip > querier.zip.sha256)

echo "==> ${OUT_ZIP}"
cat "${OUT_ZIP}.sha256"
