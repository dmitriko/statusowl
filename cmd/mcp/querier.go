// Querier client: the only AWS surface in this binary.
//
// Wraps aws-sdk-go-v2's Lambda Invoke into a typed Go interface. Keeps the
// raw payload shape — JSON object with code/timeout_seconds/account in,
// JSON object with stdout/stderr/exit_code/audit_id/... out — close to the
// querier Lambda's wire contract so changes there surface as one-file diffs.

package main

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/aws/aws-sdk-go-v2/aws"
	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/lambda"
	"github.com/aws/aws-sdk-go-v2/service/lambda/types"
)

// querierEvent matches the querier Lambda's input contract — see
// cmd/querier/src/querier/handler.py:_validate.
type querierEvent struct {
	Code           string `json:"code"`
	TimeoutSeconds int    `json:"timeout_seconds"`
	Account        string `json:"account,omitempty"`
}

// querierResult matches the querier Lambda's response shape — see
// cmd/querier/src/querier/handler.py:lambda_handler.
//
// Both success and validation-error responses are unmarshalled into this
// struct; on validation errors `Error` is populated and most other fields
// are empty.
type querierResult struct {
	OK         bool   `json:"ok"`
	Stdout     string `json:"stdout"`
	Stderr     string `json:"stderr"`
	ExitCode   int    `json:"exit_code"`
	DurationMs int    `json:"duration_ms"`
	TimedOut   bool   `json:"timed_out"`
	Truncated  bool   `json:"truncated"`
	AuditID    string `json:"audit_id"`
	AuditKey   string `json:"audit_key"`
	Error      string `json:"error,omitempty"`
}

type querier struct {
	client       *lambda.Client
	functionName string
}

func newQuerier(ctx context.Context, cfg *config) (*querier, error) {
	awsCfg, err := awsconfig.LoadDefaultConfig(ctx, awsconfig.WithRegion(cfg.AWSRegion))
	if err != nil {
		return nil, fmt.Errorf("load AWS config: %w", err)
	}
	return &querier{
		client:       lambda.NewFromConfig(awsCfg),
		functionName: cfg.QuerierFunctionName,
	}, nil
}

func (q *querier) invoke(ctx context.Context, ev querierEvent) (*querierResult, error) {
	payload, err := json.Marshal(ev)
	if err != nil {
		return nil, fmt.Errorf("marshal event: %w", err)
	}

	out, err := q.client.Invoke(ctx, &lambda.InvokeInput{
		FunctionName:   aws.String(q.functionName),
		InvocationType: types.InvocationTypeRequestResponse,
		Payload:        payload,
	})
	if err != nil {
		return nil, fmt.Errorf("lambda.Invoke: %w", err)
	}

	// FunctionError signals the Lambda raised an unhandled exception. The
	// payload is then a Lambda-side error envelope, not our querierResult.
	if out.FunctionError != nil {
		return nil, fmt.Errorf("querier raised %s: %s", *out.FunctionError, string(out.Payload))
	}

	var result querierResult
	if err := json.Unmarshal(out.Payload, &result); err != nil {
		return nil, fmt.Errorf("unmarshal querier response: %w (payload=%s)", err, string(out.Payload))
	}
	return &result, nil
}
