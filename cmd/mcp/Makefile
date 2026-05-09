.PHONY: build-mcp test-mcp-local vet clean

BIN := dist/statusowl-mcp

build-mcp:
	@mkdir -p dist
	go build -trimpath -ldflags="-s -w" -o $(BIN) ./...

vet:
	go vet ./...

# Spawns the binary, sends an MCP initialize handshake + tools/list, and
# greps for run_python in the response. The script sets a dummy querier
# function name — we're only exercising the protocol surface, not invoking.
test-mcp-local: build-mcp
	./scripts/smoke.sh $(BIN)

clean:
	rm -rf dist
