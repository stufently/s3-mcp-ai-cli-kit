package mcpserver

import (
	"github.com/stufently/s3-mcp-ai-cli-kit/config"
	"github.com/stufently/s3-mcp-ai-cli-kit/internal/testprofile"
	"os"
	"sort"
	"strings"
	"testing"
)

func TestProfileRegistrationMatrix(t *testing.T) {
	raw, err := os.ReadFile("../testdata/tools/all.golden")
	if err != nil {
		t.Fatal(err)
	}
	names := append(strings.Fields(string(raw)), "s3_get_object_tagging", "s3_put_object_tagging", "s3_download_file", "s3_upload_file")
	requirements := map[string]int{}
	for _, name := range strings.Fields("s3_put_object s3_create_folder s3_copy_object s3_presign_put s3_multipart_create s3_multipart_presign_part s3_multipart_complete s3_put_object_tagging s3_upload_file") {
		requirements[name] = 1
	}
	for _, name := range strings.Fields("s3_delete_object s3_delete_objects s3_multipart_abort") {
		requirements[name] = 2
	}
	for _, name := range strings.Fields("s3_create_bucket s3_put_bucket_versioning s3_put_bucket_cors s3_put_bucket_policy s3_delete_bucket_policy s3_put_object_lock_configuration") {
		requirements[name] = 4
	}
	requirements["s3_move_object"] = 3
	requirements["s3_delete_bucket"] = 6
	groups := []struct{ feature, tools string }{
		{"bucket_create", "s3_create_bucket"}, {"bucket_delete", "s3_delete_bucket"}, {"bucket_config", "s3_get_bucket_config"},
		{"versioning", "s3_list_object_versions s3_put_bucket_versioning"},
		{"object_tagging", "s3_get_object_tagging s3_put_object_tagging"},
		{"cors", "s3_put_bucket_cors"}, {"bucket_policy", "s3_put_bucket_policy s3_delete_bucket_policy"},
		{"object_lock_config", "s3_put_object_lock_configuration"},
		{"multipart", "s3_list_multipart_uploads s3_list_parts s3_unfinished_uploads s3_multipart_create s3_multipart_presign_part s3_multipart_complete s3_multipart_abort s3_upload_file"},
		{"presign", "s3_presign_get s3_presign_put s3_multipart_presign_part"}, {"conditional_delete", "s3_move_object"},
	}
	base, err := testprofile.Load()
	if err != nil {
		t.Fatal(err)
	}
	for caps := 0; caps < 1<<len(groups); caps++ {
		for mask := 0; mask < 8; mask++ {
			for _, root := range []string{"", "root"} {
				p := base
				p.Features = make(map[string]bool)
				disabled := map[string]bool{}
				for bit, group := range groups {
					enabled := caps&(1<<bit) != 0
					p.Features[group.feature] = enabled
					if !enabled {
						for _, name := range strings.Fields(group.tools) {
							disabled[name] = true
						}
					}
				}
				expected := []string{}
				for _, name := range names {
					if disabled[name] || mask&requirements[name] != requirements[name] || root == "" && (name == "s3_download_file" || name == "s3_upload_file") {
						continue
					}
					expected = append(expected, name)
				}
				actual := []string{}
				for _, spec := range Tools(p, config.Config{Allow: map[string]bool{"write": mask&1 != 0, "delete": mask&2 != 0, "admin": mask&4 != 0}, FileRoot: root}) {
					actual = append(actual, spec.Name)
				}
				sort.Strings(expected)
				sort.Strings(actual)
				if strings.Join(actual, " ") != strings.Join(expected, " ") {
					t.Fatalf("PROFILE_REGISTRY: caps=%d levels=%d root=%q got=%v expected=%v", caps, mask, root, actual, expected)
				}
			}
		}
	}
}
