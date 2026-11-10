package mcpserver

import (
	"strings"
	"testing"
)

// Every registered tool and every input property carries a description, and
// tool-specific overrides only name real tools and fields.
func TestToolAndParameterDescriptions(t *testing.T) {
	fields := map[string]bool{}
	for _, spec := range registry {
		if len(spec.Description) < 80 {
			t.Errorf("DESCRIPTIONS: %s description too short: %q", spec.Name, spec.Description)
		}
		schema := inputSchema(spec)
		for _, field := range strings.Fields(spec.Fields) {
			fields[spec.Name+":"+field] = true
			fields[field] = true
			if schema.Properties[field].Description == "" {
				t.Errorf("DESCRIPTIONS: %s.%s has no description", spec.Name, field)
			}
		}
	}
	for key := range paramDescriptions {
		if !fields[key] {
			t.Errorf("DESCRIPTIONS: description %q matches no tool field", key)
		}
	}
	if got := paramDescription("s3_copy_object", "key"); got != paramDescriptions["s3_copy_object:key"] {
		t.Errorf("DESCRIPTIONS: override not applied: %q", got)
	}
	if got := paramDescription("s3_head_object", "key"); got != paramDescriptions["key"] {
		t.Errorf("DESCRIPTIONS: shared description not applied: %q", got)
	}
}
