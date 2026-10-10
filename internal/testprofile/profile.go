// Package testprofile provides the accepted baseline only for tests and examples.
package testprofile

import (
	_ "embed"
	"github.com/stufently/s3-mcp-ai-cli-kit/provider"
)

//go:embed profile.yaml
var data []byte

func Load() (provider.Profile, error) { return provider.Load(data) }
