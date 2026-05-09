// run_python tool: the only tool in this pass.
//
// The tool description is the most important code in this file — it's what
// makes the model reach for run_python at the right moments. Iterate on it
// once we've used it for real, based on whether the model fumbles or finds
// it reliably.

package main

import (
	"context"
	"fmt"
	"os"
	"strings"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

const runPythonDescription = `Run a Python script in the statusowl querier Lambda for read-only AWS investigation. Reach for this tool whenever you need to inspect AWS state — check ECS service health, list S3 contents, query CloudWatch metrics, walk IAM roles, anything where you'd otherwise want a shell with boto3.

The code runs in a Lambda sandbox under a narrow IAM role: AWS ReadOnlyAccess minus IAM enumeration, no internet egress beyond AWS APIs, hard time/memory bounds. ` + "`boto3`" + ` is in scope; the Python standard library is available; nothing else. Every invocation is audited (code, args, stdout/stderr, duration) to S3.

Stdout from your script is returned to you; structure your output for whoever's asking. Use ` + "`print()`" + ` for results — the tool returns whatever your script writes.`

type runPythonInput struct {
	Code           string `json:"code" jsonschema:"Python source to execute. Use boto3 for AWS calls; print() to return results."`
	TimeoutSeconds int    `json:"timeout_seconds,omitempty" jsonschema:"Soft per-invocation timeout in seconds (default 30, max 60)."`
	Account        string `json:"account,omitempty" jsonschema:"Optional account name from the registry. If set the querier assumes that account's read-only role before running. Omit for the default (hub) account."`
}

const (
	defaultTimeoutSeconds = 30
	maxTimeoutSeconds     = 60
)

func registerRunPython(srv *mcp.Server, q *querier, debug bool) {
	mcp.AddTool(srv, &mcp.Tool{
		Name:        "run_python",
		Description: runPythonDescription,
	}, func(ctx context.Context, _ *mcp.CallToolRequest, in runPythonInput) (*mcp.CallToolResult, any, error) {
		return handleRunPython(ctx, q, in, debug)
	})
}

func handleRunPython(ctx context.Context, q *querier, in runPythonInput, debug bool) (*mcp.CallToolResult, any, error) {
	if strings.TrimSpace(in.Code) == "" {
		return &mcp.CallToolResult{
			IsError: true,
			Content: []mcp.Content{&mcp.TextContent{Text: "code must not be empty"}},
		}, nil, nil
	}

	timeout := in.TimeoutSeconds
	if timeout <= 0 {
		timeout = defaultTimeoutSeconds
	}
	if timeout > maxTimeoutSeconds {
		timeout = maxTimeoutSeconds
	}

	res, err := q.invoke(ctx, querierEvent{
		Code:           in.Code,
		TimeoutSeconds: timeout,
		Account:        in.Account,
	})
	if err != nil {
		// Transport-level failure (Lambda not reachable, IAM denied, etc.).
		// Surface as a tool-level error, not a protocol error, so the model
		// can see the message and self-correct.
		return &mcp.CallToolResult{
			IsError: true,
			Content: []mcp.Content{&mcp.TextContent{Text: fmt.Sprintf("querier invoke failed: %v", err)}},
		}, nil, nil
	}

	logInvocation(in, res, debug)

	return &mcp.CallToolResult{
		IsError: !res.OK,
		Content: []mcp.Content{&mcp.TextContent{Text: formatResult(res)}},
	}, nil, nil
}

// formatResult builds the text the model sees. Success cases get clean stdout
// (the model rarely needs the metadata). Failures get stderr, exit code, and
// the audit_id so the user can look up the full record in S3.
func formatResult(r *querierResult) string {
	if r.OK && !r.TimedOut && r.ExitCode == 0 {
		return r.Stdout
	}

	var b strings.Builder
	if r.Error != "" {
		fmt.Fprintf(&b, "validation error: %s\n", r.Error)
	}
	if r.Stdout != "" {
		b.WriteString(r.Stdout)
		if !strings.HasSuffix(r.Stdout, "\n") {
			b.WriteByte('\n')
		}
	}
	if r.Stderr != "" {
		b.WriteString("--- stderr ---\n")
		b.WriteString(r.Stderr)
		if !strings.HasSuffix(r.Stderr, "\n") {
			b.WriteByte('\n')
		}
	}

	fmt.Fprintf(&b, "--- exit_code=%d", r.ExitCode)
	if r.TimedOut {
		b.WriteString(" (timed out)")
	}
	if r.Truncated {
		b.WriteString(" (output truncated)")
	}
	if r.AuditID != "" {
		fmt.Fprintf(&b, " audit_id=%s", r.AuditID)
	}
	b.WriteString(" ---")

	return b.String()
}

func logInvocation(in runPythonInput, r *querierResult, debug bool) {
	if !debug {
		return
	}
	fmt.Fprintf(os.Stderr,
		"statusowl-mcp: tool=run_python ok=%t exit_code=%d timed_out=%t duration_ms=%d audit_id=%s account=%q code_bytes=%d\n",
		r.OK, r.ExitCode, r.TimedOut, r.DurationMs, r.AuditID, in.Account, len(in.Code),
	)
}
