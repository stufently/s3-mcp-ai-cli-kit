package s3core

import (
	"bytes"
	"context"
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
