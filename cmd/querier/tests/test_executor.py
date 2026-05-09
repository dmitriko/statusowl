import time

from querier import executor


def test_simple_code_runs_and_captures_stdout():
    result = executor.run_code("print('hello')", timeout_seconds=5)
    assert result.exit_code == 0
    assert result.stdout.strip() == "hello"
    assert result.stderr == ""
    assert not result.timed_out
    assert not result.truncated


def test_stderr_is_captured():
    result = executor.run_code(
        "import sys; sys.stderr.write('oops\\n')",
        timeout_seconds=5,
    )
    assert result.exit_code == 0
    assert "oops" in result.stderr


def test_nonzero_exit_propagates():
    result = executor.run_code("raise SystemExit(2)", timeout_seconds=5)
    assert result.exit_code == 2


def test_timeout_kills_long_running_code():
    start = time.monotonic()
    result = executor.run_code("import time; time.sleep(10)", timeout_seconds=1)
    elapsed = time.monotonic() - start
    assert result.timed_out
    assert elapsed < 5  # killed promptly, not waiting the full 10s
    assert "timeout" in result.stderr.lower()


def test_oversized_stdout_is_truncated():
    code = "print('x' * (2 * 1024 * 1024))"  # 2 MiB
    result = executor.run_code(code, timeout_seconds=10)
    assert result.truncated
    assert len(result.stdout.encode("utf-8")) <= executor.MAX_OUTPUT_BYTES


def test_extra_env_is_visible_to_child():
    result = executor.run_code(
        "import os; print(os.environ.get('STATUSOWL_TEST'))",
        timeout_seconds=5,
        extra_env={"STATUSOWL_TEST": "from-parent"},
    )
    assert result.stdout.strip() == "from-parent"


def test_isolated_mode_blocks_pythonpath_pivot(monkeypatch, tmp_path):
    # -I should ignore PYTHONPATH so generated code can't import an
    # attacker-controlled module by setting env vars.
    monkeypatch.setenv("PYTHONPATH", str(tmp_path))
    (tmp_path / "evil.py").write_text("X = 'pivoted'")
    result = executor.run_code(
        "try:\n"
        "    import evil\n"
        "    print('LOADED', evil.X)\n"
        "except ImportError:\n"
        "    print('blocked')\n",
        timeout_seconds=5,
    )
    assert result.stdout.strip() == "blocked"
