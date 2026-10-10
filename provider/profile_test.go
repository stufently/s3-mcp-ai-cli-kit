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

func TestFeatureDefaults(t *testing.T) {
	for _, name := range []string{"bucket_create", "bucket_delete", "bucket_config", "versioning", "cors", "multipart", "presign", "conditional_writes", "conditional_delete", "unknown"} {
		for _, state := range []string{"missing", "false", "true"} {
			p := Profile{Features: map[string]bool{}}
			if state != "missing" {
				p.Features[name] = state == "true"
			}
			want := state == "true" || state == "missing" && (name == "bucket_create" || name == "bucket_delete" || name == "bucket_config")
			if got := p.Supports(name); got != want {
				t.Fatalf("FEATURE_DEFAULT: feature=%s state=%s got=%t want=%t", name, state, got, want)
			}
		}
	}
}
