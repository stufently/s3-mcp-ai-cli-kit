//go:build ignore

package main

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"github.com/stufently/s3-mcp-ai-cli-kit/config"
	"github.com/stufently/s3-mcp-ai-cli-kit/mcpserver"
	"github.com/stufently/s3-mcp-ai-cli-kit/provider"
	"os"
	"os/exec"
	"sort"
	"strings"
	"time"
)

func main() {
	raw, e := os.ReadFile(os.Args[2])
	if e != nil {
		panic(e)
	}
	p, e := provider.Load(raw)
	if e != nil {
		panic(e)
	}
	for mask := 0; mask < 8; mask++ {
		item := struct {
			name  string
			flags []string
		}{name: fmt.Sprintf("levels-%d", mask)}
		allow := map[string]bool{}
		for bit, level := range []string{"write", "delete", "admin"} {
			allow[level] = mask&(1<<bit) != 0
			item.flags = append(item.flags, fmt.Sprintf("--allow-%s=%t", level, allow[level]))
		}

		ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
		cmd := exec.CommandContext(ctx, os.Args[1], append([]string{"mcp"}, item.flags...)...)
		cmd.Env = append(os.Environ(), p.EnvPrefix+"ACCESS_KEY_ID=fake", p.EnvPrefix+"SECRET_ACCESS_KEY=fake-secret", p.EnvPrefix+"POOL="+p.DefaultPool, p.EnvPrefix+"ENDPOINT=http://127.0.0.1:1", p.EnvPrefix+"ALLOW_INSECURE=1", p.EnvPrefix+"FILE_ROOT=", p.EnvPrefix+"ALLOW=")
		var stderr bytes.Buffer
		cmd.Stderr = &stderr
		in, e := cmd.StdinPipe()
		if e != nil {
			panic(e)
		}
		out, e := cmd.StdoutPipe()
		if e != nil {
			panic(e)
		}
		if e = cmd.Start(); e != nil {
			panic(e)
		}
		encoder := json.NewEncoder(in)
		scan := bufio.NewScanner(out)
		scan.Buffer(make([]byte, 65536), 1024*1024)
		send := func(v any) {
			if e := encoder.Encode(v); e != nil {
				panic(e)
			}
		}
		read := func(id int) map[string]any {
			for scan.Scan() {
				var result map[string]any
				if e := json.Unmarshal(scan.Bytes(), &result); e != nil {
					panic(e)
				}
				if result["id"] == float64(id) {
					if result["error"] != nil {
						panic(fmt.Sprint(result["error"]))
					}
					return result
				}
			}
			panic("missing MCP response: " + stderr.String())
		}
		send(map[string]any{"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": map[string]any{"protocolVersion": "2025-11-25", "capabilities": map[string]any{}, "clientInfo": map[string]any{"name": "stdio-smoke", "version": "1"}}})
		read(1)
		send(map[string]any{"jsonrpc": "2.0", "method": "notifications/initialized"})
		send(map[string]any{"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": map[string]any{}})
		response := read(2)
		result := response["result"].(map[string]any)
		names := []string{}
		for _, tool := range result["tools"].([]any) {
			names = append(names, tool.(map[string]any)["name"].(string))
		}
		sort.Strings(names)
		expected := []string{}
		for _, spec := range mcpserver.Tools(p, config.Config{Allow: allow}) {
			expected = append(expected, spec.Name)
		}
		sort.Strings(expected)
		if strings.Join(names, "\n") != strings.Join(expected, "\n") {
			panic(fmt.Sprintf("%s tools mismatch: got=%v expected=%v", item.name, names, expected))
		}

		if e = in.Close(); e != nil {
			panic(e)
		}
		if e = cmd.Wait(); e != nil {
			panic(fmt.Sprintf("MCP exit: %v %s", e, stderr.String()))
		}
		cancel()
		fmt.Printf("%s: %d tools OK\n", item.name, len(names))
	}
}
