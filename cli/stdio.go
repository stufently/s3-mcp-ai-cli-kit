package cli

import (
	"context"
	"github.com/modelcontextprotocol/go-sdk/mcp"
	"github.com/stufently/s3-mcp-ai-cli-kit/mcpserver"
)

func runStdio(ctx context.Context, server *mcpserver.Server) error {
	return server.MCP.Run(ctx, &mcp.StdioTransport{})
}
