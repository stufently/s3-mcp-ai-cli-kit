package skills

import (
	"github.com/stufently/s3-mcp-ai-cli-kit/provider"
	"strings"
	"testing"
)

func TestRenderProviderMatrix(t *testing.T) {
	for _, id := range []string{"selectel", "yandex", "vkcloud", "cloudru", "timeweb", "mws", "beget"} {
		t.Run(id, func(t *testing.T) {
			p := provider.Profile{ID: id, Binary: id + "-s3", DisplayName: id, DefaultPool: "test-region", URIScheme: id + "-resources", PresignMaxSeconds: 3600, DocsURLs: []string{"https://example.test/" + id}}
			for _, name := range []string{"template/SKILL.md", "template/references/backup-restore.md", "template/references/share-file.md", "template/references/least-privilege.md", "template/references/cost-hygiene.md", "template/references/migration.md", "template/references/incident-response.md"} {
				raw, e := Files.ReadFile(name)
				if e != nil {
					t.Fatal(e)
				}
				text := Render(string(raw), p)
				if strings.Contains(text, "{{") || id != "selectel" && strings.Contains(strings.ToLower(text), "selectel") || strings.Contains(text, "ru-3") || strings.Contains(text, "2,56") {
					t.Fatalf("provider template leaked facts: %s", name)
				}
				if name == "template/SKILL.md" && (!strings.Contains(text, "name: "+p.Binary) || !strings.Contains(text, p.URIScheme+"://config")) {
					t.Fatalf("skill identity lost: %s", text)
				}
			}
		})
	}
}
