// statusowl-mcp: a Model Context Protocol server that exposes the deployed
// statusowl querier Lambda as MCP tools over stdio.
//
// SDK: github.com/modelcontextprotocol/go-sdk — the official MCP Go SDK,
// jointly maintained by the Anthropic and Google Cloud teams under the
// modelcontextprotocol org. Chosen over mark3labs/mcp-go because (1) it's
// the spec authority and ships protocol updates first, (2) it generates
// JSON schemas from typed Go structs via generics, and (3) third-party
// alternatives predate it and several of their design choices have been
// superseded.
//
// Scope: stdio transport, Claude Code as the local consumer. Lambda
// deployment with HTTP/Function-URL transport will land once the tool
// surface stabilizes.

package main

import (
	"context"
	"fmt"
	"os"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

const (
	serverName    = "statusowl"
	serverVersion = "0.1.0"
)

func main() {
	if err := run(); err != nil {
		fmt.Fprintf(os.Stderr, "statusowl-mcp: %v\n", err)
		os.Exit(1)
	}
}

func run() error {
	ctx := context.Background()

	cfg, err := loadConfig()
	if err != nil {
		return fmt.Errorf("config: %w", err)
	}

	q, err := newQuerier(ctx, cfg)
	if err != nil {
		return fmt.Errorf("querier client: %w", err)
	}

	srv := mcp.NewServer(&mcp.Implementation{
		Name:    serverName,
		Version: serverVersion,
	}, nil)

	registerRunPython(srv, q, cfg.Debug)

	mode := "stdio"
	if isLambda() {
		mode = "lambda"
	}

	if cfg.Debug {
		fmt.Fprintf(os.Stderr,
			"statusowl-mcp: ready (mode=%s function=%s region=%s)\n",
			mode, cfg.QuerierFunctionName, cfg.AWSRegion,
		)
	}

	if isLambda() {
		return runLambda(ctx, srv)
	}
	return srv.Run(ctx, &mcp.StdioTransport{})
}

// isLambda reports whether we're running inside an AWS Lambda execution
// environment. AWS_LAMBDA_FUNCTION_NAME is set automatically by the runtime.
func isLambda() bool {
	return os.Getenv("AWS_LAMBDA_FUNCTION_NAME") != ""
}
