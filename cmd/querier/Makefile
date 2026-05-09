.PHONY: install test lint format local-run build-querier clean

install:
	uv sync

test:
	uv run pytest

lint:
	uv run ruff check .

format:
	uv run ruff format .

EVENT ?= scripts/sample_event.json

local-run:
	uv run python scripts/invoke_local.py --event $(EVENT)

# Produces the same deterministic zip the GitHub release workflow ships.
# Single source of truth: scripts/build-querier.sh at the repo root.
build-querier:
	../../scripts/build-querier.sh

clean:
	rm -rf .venv .pytest_cache .ruff_cache dist build
	find . -type d -name __pycache__ -exec rm -rf {} +
