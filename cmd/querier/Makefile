.PHONY: install test lint format local-run clean

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

clean:
	rm -rf .venv .pytest_cache .ruff_cache dist
	find . -type d -name __pycache__ -exec rm -rf {} +
