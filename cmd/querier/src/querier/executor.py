"""Subprocess-based execution of LLM-generated Python with bounds.

This is the trust boundary: code arrives from the model, runs here, and
must not exceed the time/memory/output ceilings the Lambda promises.
"""

from __future__ import annotations

import contextlib
import os
import resource
import subprocess
import sys
import time
from collections.abc import Mapping
from dataclasses import dataclass

from . import config

MAX_OUTPUT_BYTES = 1024 * 1024  # 1 MiB per stream


@dataclass(frozen=True)
class ExecutionResult:
    stdout: str
    stderr: str
    exit_code: int
    duration_ms: int
    timed_out: bool
    truncated: bool


def _preexec_set_limits() -> None:
    # RLIMIT_AS bounds virtual address space, which on Linux is a
    # reasonable proxy for memory. macOS often ignores it; we still call
    # it so Lambda (Linux) gets the bound, and fall back silently locally.
    mem = config.mem_limit_mb()
    if mem is None:
        return
    limit_bytes = mem * 1024 * 1024
    with contextlib.suppress(ValueError, OSError):
        resource.setrlimit(resource.RLIMIT_AS, (limit_bytes, limit_bytes))


def _truncate(text: str) -> tuple[str, bool]:
    encoded = text.encode("utf-8")
    if len(encoded) <= MAX_OUTPUT_BYTES:
        return text, False
    return encoded[:MAX_OUTPUT_BYTES].decode("utf-8", errors="replace"), True


def run_code(
    code: str,
    timeout_seconds: int,
    extra_env: Mapping[str, str] | None = None,
) -> ExecutionResult:
    """Run `code` in a child Python interpreter under bounds."""
    timeout_seconds = min(max(1, timeout_seconds), config.max_timeout_s())

    env = os.environ.copy()
    if extra_env:
        env.update(extra_env)

    start = time.monotonic()
    timed_out = False

    try:
        proc = subprocess.run(
            # -I: isolated mode. Ignores PYTHON* env vars and skips user
            # site-packages, so generated code can't pivot via env tricks.
            [sys.executable, "-I", "-"],
            input=code,
            capture_output=True,
            text=True,
            timeout=timeout_seconds,
            env=env,
            preexec_fn=_preexec_set_limits if sys.platform == "linux" else None,
            check=False,
        )
        stdout = proc.stdout or ""
        stderr = proc.stderr or ""
        exit_code = proc.returncode
    except subprocess.TimeoutExpired as exc:
        timed_out = True
        stdout = _coerce(exc.stdout)
        stderr = _coerce(exc.stderr) + f"\n[statusowl] killed after {timeout_seconds}s timeout\n"
        exit_code = -9

    duration_ms = int((time.monotonic() - start) * 1000)
    stdout, t1 = _truncate(stdout)
    stderr, t2 = _truncate(stderr)

    return ExecutionResult(
        stdout=stdout,
        stderr=stderr,
        exit_code=exit_code,
        duration_ms=duration_ms,
        timed_out=timed_out,
        truncated=t1 or t2,
    )


def _coerce(buf: str | bytes | None) -> str:
    if buf is None:
        return ""
    if isinstance(buf, (bytes, bytearray)):
        return buf.decode("utf-8", errors="replace")
    return buf
