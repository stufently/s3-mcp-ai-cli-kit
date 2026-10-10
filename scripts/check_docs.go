//go:build ignore

package main

import (
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"github.com/google/jsonschema-go/jsonschema"
	"github.com/stufently/s3-mcp-ai-cli-kit/provider"
	"os"
	"os/exec"
	"strings"
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
	headings := map[string][]string{
		"README.md":    {"# " + p.DisplayName + " S3 MCP Server & AI CLI", "## English", "## Возможности", "## Быстрый старт", "## Подключение к Claude Code, Cursor, Codex", "## Инструменты MCP", "## CLI", "## Skill для AI-агентов", "## Безопасность", "## Пулы и классы хранения " + p.DisplayName + "", "## FAQ", "## Другие провайдеры", "## Лицензия"},
		"README.en.md": {"# " + p.DisplayName + " S3 MCP Server & AI CLI", "## Features", "## Quick start", "## Connect to Claude Code, Cursor, Codex", "## MCP tools", "## CLI", "## Agent skill", "## Security", "## " + p.DisplayName + " pools and storage classes", "## FAQ", "## License"},
	}
	for path, required := range headings {
		data, e := os.ReadFile(path)
		if e != nil {
			panic(e)
		}
		lines := "\n" + string(data) + "\n"
		for _, heading := range required {
			if !strings.Contains(lines, "\n"+heading+"\n") {
				panic(path + ": missing " + heading)
			}
		}
	}
	generated, e := exec.Command(os.Args[1], "compat", "--markdown").Output()
	if e != nil {
		panic(e)
	}
	checked, e := os.ReadFile("docs/compat.md")
	if e != nil {
		panic(e)
	}
	if string(generated) != string(checked) {
		panic("compat output differs from docs/compat.md")
	}
	schema, e := os.ReadFile(os.Args[3])
	if e != nil {
		panic(e)
	}
	if fmt.Sprintf("%x", sha256.Sum256(schema)) != "3fba09590c99f61735d234822279f4223fab9e300c0a81e81c91ab62a4114de0" {
		panic("schema sha256 differs")
	}
	var def jsonschema.Schema
	if e = json.Unmarshal(schema, &def); e != nil {
		panic(e)
	}
	resolved, e := def.Resolve(nil)
	if e != nil {
		panic(e)
	}
	manifest, e := os.ReadFile("server.json")
	if e != nil {
		panic(e)
	}
	var value any
	if e = json.Unmarshal(manifest, &value); e != nil {
		panic(e)
	}
	if e = resolved.Validate(value); e != nil {
		panic(e)
	}
	fmt.Println("documentation headings, generated compatibility and Registry schema hash OK")
}
