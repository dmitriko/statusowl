// Lambda-mode entry point for the MCP server.
//
// When AWS_LAMBDA_FUNCTION_NAME is set, main() calls runLambda. The MCP
// server is wrapped in a stateless StreamableHTTP handler, then bridged to
// Lambda Function URL events via aws-lambda-go-api-proxy. Stateless mode
// matches the Lambda invocation model (each request is independent), and
// JSONResponse=true keeps replies as single JSON bodies — Function URL
// response streaming is supported but unnecessary for the request/response
// shape of every tool we're shipping.

package main

import (
	"context"
	"net/http"

	"github.com/aws/aws-lambda-go/lambda"
	"github.com/awslabs/aws-lambda-go-api-proxy/httpadapter"
	"github.com/modelcontextprotocol/go-sdk/mcp"
)

func runLambda(ctx context.Context, srv *mcp.Server) error {
	handler := mcp.NewStreamableHTTPHandler(
		func(*http.Request) *mcp.Server { return srv },
		&mcp.StreamableHTTPOptions{
			Stateless:    true,
			JSONResponse: true,
		},
	)
	adapter := httpadapter.NewV2(handler)
	lambda.StartWithOptions(adapter.ProxyWithContext, lambda.WithContext(ctx))
	return nil
}
