package provider

import (
	"strings"
	"testing"
)

func TestLoadProfile(t *testing.T) {
	valid := "id: sample\ndisplay_name: Sample\nbinary: sample-s3\nenv_prefix: SAMPLE_S3_\nuri_scheme: sample-s3\ndefault_pool: test\npools:\n  - id: test\n    endpoint: https://s3.example.test\npresign_max_seconds: 3600\n"
	for _, tc := range []struct{ name, data, reason string }{
		{"valid", valid, ""}, {"missing-binary", strings.ReplaceAll(valid, "binary: sample-s3\n", ""), "invalid provider profile"},
		{"no-pools", "binary: sample-s3\nenv_prefix: SAMPLE_S3_\n", "invalid provider profile"}, {"bad-yaml", "[", "yaml"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			p, e := Load([]byte(tc.data))
			if tc.reason == "" {
				if e != nil || p.Binary != "sample-s3" {
					t.Fatalf("profile roundtrip: %+v %v", p, e)
				}
			} else if e == nil || !strings.Contains(e.Error(), tc.reason) {
				t.Fatalf("profile refusal reason %q: %v", tc.reason, e)
			}
		})
	}
}
