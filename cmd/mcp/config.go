// Env-var configuration for the MCP server.
//
// Kept in its own file so the env-var contract is reviewable in one place,
// independent of MCP server wiring or AWS code.

package main

import (
	"fmt"
	"os"
	"strconv"
)

const (
	envQuerierFunctionName = "STATUSOWL_QUERIER_FUNCTION_NAME"
	envAWSRegion           = "STATUSOWL_AWS_REGION"
	envDebug               = "STATUSOWL_DEBUG"

	defaultAWSRegion = "us-east-1"
)

type config struct {
	QuerierFunctionName string
	AWSRegion           string
	Debug               bool
}

func loadConfig() (*config, error) {
	fn := os.Getenv(envQuerierFunctionName)
	if fn == "" {
		return nil, fmt.Errorf("%s is required (the deployed querier Lambda's name or ARN)", envQuerierFunctionName)
	}

	region := os.Getenv(envAWSRegion)
	if region == "" {
		region = defaultAWSRegion
	}

	debug := false
	if raw := os.Getenv(envDebug); raw != "" {
		v, err := strconv.ParseBool(raw)
		if err != nil {
			return nil, fmt.Errorf("%s: %w", envDebug, err)
		}
		debug = v
	}

	return &config{
		QuerierFunctionName: fn,
		AWSRegion:           region,
		Debug:               debug,
	}, nil
}
