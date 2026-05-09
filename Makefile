# statusowl — repo-root Makefile.
#
# Single entry point. Targets are component-suffixed (querier-*, mcp-*).
# All targets are designed to run from the repo root.

QUERIER_DIR := cmd/querier
MCP_DIR     := cmd/mcp
MCP_BIN     := $(MCP_DIR)/dist/statusowl-mcp

.PHONY: help \
        install-querier test-querier lint-querier format-querier local-run-querier build-querier \
        build-mcp vet-mcp test-mcp-local \
        test lint clean

help: ## list available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}'

# --- querier (Python Lambda) ---

install-querier: ## sync querier dev deps via uv
	cd $(QUERIER_DIR) && uv sync

test-querier: ## pytest the querier
	cd $(QUERIER_DIR) && uv run pytest

lint-querier: ## ruff-check the querier
	cd $(QUERIER_DIR) && uv run ruff check .

format-querier: ## ruff-format the querier
	cd $(QUERIER_DIR) && uv run ruff format .

QUERIER_EVENT ?= scripts/sample_event.json
local-run-querier: ## invoke querier handler locally with moto-mocked S3 (override with QUERIER_EVENT=...)
	cd $(QUERIER_DIR) && uv run python scripts/invoke_local.py --event $(QUERIER_EVENT)

build-querier: ## build the deterministic querier Lambda zip + sha256
	./scripts/build-querier.sh

# --- mcp (Go server) ---

build-mcp: ## build the MCP server binary
	@mkdir -p $(MCP_DIR)/dist
	cd $(MCP_DIR) && go build -trimpath -ldflags="-s -w" -o dist/statusowl-mcp ./...

vet-mcp: ## go vet the MCP server
	cd $(MCP_DIR) && go vet ./...

test-mcp-local: build-mcp ## protocol smoke test for the MCP server (no AWS calls)
	$(MCP_DIR)/scripts/smoke.sh $(MCP_BIN)

# --- aggregates ---

test: test-querier test-mcp-local ## run all tests

lint: lint-querier vet-mcp ## run all linters

clean: ## remove build/test artifacts everywhere
	cd $(QUERIER_DIR) && rm -rf .venv .pytest_cache .ruff_cache dist build
	find $(QUERIER_DIR) -type d -name __pycache__ -exec rm -rf {} +
	rm -rf $(MCP_DIR)/dist
