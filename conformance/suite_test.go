//go:build conformance

package conformance

import (
	"github.com/stufently/s3-mcp-ai-cli-kit/internal/testprofile"
	"testing"
)

func TestS3(t *testing.T) {
	p, e := testprofile.Load()
	if e != nil {
		t.Fatal(e)
	}
	p.Features["object_tagging"] = true
	RunS3(t, p)
}
func TestMCP(t *testing.T) {
	p, e := testprofile.Load()
	if e != nil {
		t.Fatal(e)
	}
	RunMCP(t, p)
}
func TestCLI(t *testing.T) {
	p, e := testprofile.Load()
	if e != nil {
		t.Fatal(e)
	}
	RunCLI(t, p)
}

func TestDisabledCapabilities(t *testing.T) {
	p, e := testprofile.Load()
	if e != nil {
		t.Fatal(e)
	}
	p.Features["bucket_create"] = false
	p.Features["bucket_delete"] = false
	p.Features["bucket_config"] = false
	for feature := range p.Features {
		p.Features[feature] = false
	}
	t.Run("S3", func(t *testing.T) { RunS3(t, p) })
	t.Run("MCP", func(t *testing.T) { RunMCP(t, p) })
	// CLI conformance builds the real embedded profile, so disabled-profile
	// variants are tested through core/MCP here and provider-specific CLI runs.
}
