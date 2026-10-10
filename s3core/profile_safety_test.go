package s3core

import (
	"bytes"
	"context"
	"fmt"
	"net/http"
	"strings"
	"sync/atomic"
	"testing"
)

func TestUnsupportedConditionalWriteRefusal(t *testing.T) {
	for _, name := range []string{"s3_put_object", "s3_create_folder", "s3_copy_object", "s3_move_object", "s3_multipart_complete", "upload_reader"} {
		t.Run(name, func(t *testing.T) {
			var requests atomic.Int32
			c := testClient(t, func(w http.ResponseWriter, r *http.Request) { requests.Add(1); w.WriteHeader(404) }, "allow")
			c.Profile.Features["conditional_writes"] = false
			a := Args{Bucket: "bucket", Key: "key", SourceBucket: "bucket", SourceKey: "source", UploadID: "upload", Parts: []Part{{Number: 1, ETag: "etag"}}}
			var err error
			if name == "upload_reader" {
				_, err = c.UploadReader(context.Background(), a, bytes.NewReader([]byte("data")), nil)
			} else {
				_, err = c.Execute(context.Background(), name, a, nil)
			}
			if err == nil || !strings.Contains(err.Error(), "conditional writes unsupported; overwrite:true requires destructive approval") || requests.Load() != 0 {
				t.Fatalf("PROFILE_WRITE: tool=%s requests=%d err=%v", name, requests.Load(), err)
			}
		})
	}
}
func TestUnsupportedConditionalDeleteRefusal(t *testing.T) {
	for _, overwrite := range []bool{false, true} {
		t.Run(map[bool]string{false: "default", true: "overwrite"}[overwrite], func(t *testing.T) {
			var requests atomic.Int32
			c := testClient(t, func(w http.ResponseWriter, r *http.Request) { requests.Add(1); w.WriteHeader(404) }, "allow")
			c.Profile.Features["conditional_delete"] = false
			_, err := c.Execute(context.Background(), "s3_move_object", Args{Bucket: "bucket", Key: "key", SourceBucket: "bucket", SourceKey: "source", Overwrite: overwrite}, nil)
			if err == nil || !strings.Contains(err.Error(), "conditional delete unsupported; move disabled") || requests.Load() != 0 {
				t.Fatalf("PROFILE_MOVE: requests=%d err=%v", requests.Load(), err)
			}
		})
	}
}

func TestUnsupportedBucketOperations(t *testing.T) {
	for _, op := range []struct{ name, feature string }{
		{"s3_create_bucket", "bucket_create"}, {"s3_delete_bucket", "bucket_delete"}, {"s3_get_bucket_config", "bucket_config"},
	} {
		for mask := 0; mask < 8; mask++ {
			t.Run(fmt.Sprintf("%s/%d", op.name, mask), func(t *testing.T) {
				var requests atomic.Int32
				c := testClient(t, func(w http.ResponseWriter, _ *http.Request) { requests.Add(1); w.WriteHeader(http.StatusBadRequest) }, "allow")
				c.Config.Allow = map[string]bool{"write": mask&1 != 0, "delete": mask&2 != 0, "admin": mask&4 != 0}
				c.Profile.Features[op.feature] = false
				_, err := c.Execute(context.Background(), op.name, Args{Bucket: "bucket", Confirm: true}, nil)
				reason := op.feature + " unsupported"
				if err == nil || !strings.Contains(err.Error(), reason) || requests.Load() != 0 {
					t.Fatalf("PROFILE_BUCKET: tool=%s levels=%d requests=%d expected=%q err=%v", op.name, mask, requests.Load(), reason, err)
				}
			})
		}
	}
}
