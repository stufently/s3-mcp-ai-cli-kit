// Package skills supplies provider-neutral skill templates shipped with the binary.
package skills

import (
	"embed"
	"github.com/stufently/s3-mcp-ai-cli-kit/provider"
	"strconv"
	"strings"
)

//go:embed template/SKILL.md template/references/*.md
var Files embed.FS

// Render fills only provider identity and sourced profile facts.
func Render(text string, p provider.Profile) string {
	return strings.NewReplacer("{{binary}}", p.Binary, "{{uri_scheme}}", p.URIScheme, "{{display_name}}", p.DisplayName, "{{default_pool}}", p.DefaultPool, "{{docs_urls}}", strings.Join(p.DocsURLs, " "), "{{presign_max_seconds}}", strconv.FormatInt(p.PresignMaxSeconds, 10), "{{presign_note}}", p.PresignNote).Replace(text)
}
