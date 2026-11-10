package mcpserver

// Parameter descriptions published in each tool's input schema. A
// "tool:field" entry overrides the shared "field" entry for that tool.
var paramDescriptions = map[string]string{ //nolint:gosec // G101: parameter help text, not credentials.
	"bucket":             `Bucket name, e.g. "backups". Must be inside the configured bucket scope.`,
	"key":                `Full object key inside the bucket, without the bucket name, e.g. "daily/archive.tar".`,
	"prefix":             `Key prefix that limits the results, e.g. "daily/"; omit for the whole bucket. End it with "/" to match one folder only. In a prefix-restricted scope it must start with an allowed prefix followed by "/".`,
	"max_keys":           "Page size, 1-1000 entries; default 1000.",
	"continuation_token": "Opaque continuation_token from the previous response; omit for the first page.",
	"version_id":         "Object version ID from s3_list_object_versions; omit for the current version.",
	"version_marker":     "Version-ID marker: the version_marker from the previous page, sent together with continuation_token; omit for the first page.",
	"upload_id":          "Upload ID returned by s3_multipart_create or listed by s3_list_multipart_uploads.",
	"max_bytes":          "Largest body to accept, 1-262144 bytes; default 262144. A larger object fails instead of being truncated.",
	"encoding":           `"text" (default; fails on content that is not UTF-8) or "base64" for binary data.`,
	"data":               `Object body as UTF-8 text, or base64 when encoding is "base64", e.g. "{\"ok\":true}".`,
	"content_type":       `MIME type stored with the object, e.g. "application/json"; omit to let the provider choose.`,
	"expires_seconds":    "URL lifetime in seconds, from 1 up to the provider maximum (presign_max_seconds); default 3600 (one hour).",
	"overwrite":          "true replaces an existing destination and requires destructive approval; default false refuses an existing destination, and on providers without conditional writes refuses the write altogether.",
	"confirm":            "Set true only after a human has explicitly approved this exact destructive action. Used when the client cannot show an approval form; ignored under the allow policy and never bypasses the block or elicit policy.",
	"source_bucket":      `Bucket of the source object, e.g. "backups"; may equal bucket.`,
	"source_key":         `Key of the source object, e.g. "daily/archive.tar"; source and destination must differ.`,
	"objects":            `1-1000 objects to delete, each {"key": "daily/a.tar"} with an optional "version_id" to remove that version permanently.`,
	"parts":              `Uploaded parts in ascending part_number order, each {"part_number": 1, "etag": "\"9b2cf535f27731c974343645a3985328\""} with the ETag returned by that part's PUT.`,
	"part_number":        "Part index from 1 to the provider's max_parts limit; parts are assembled in ascending order.",
	"part_size":          "Multipart part size in bytes, at least 5242880 (5 MiB); omit for the default of 5 MiB.",
	"path":               `File path relative to the configured file root, e.g. "restore/archive.tar"; absolute paths, ".." segments and symlinks leading outside are rejected.`,
	"tags":               `Complete new tag set as a string map, e.g. {"env": "prod", "owner": "ops"}; it replaces every existing tag, and {} removes them all.`,
	"max_scan":           "Maximum number of object keys to scan in this call; default 10000. Higher values give more complete results but take longer.",
	"limit":              "Number of largest objects to return, 1-1000; default 10.",
	"result_offset":      "Row offset into the aggregated prefixes: pass next_result_offset from the previous response with the same prefix, max_scan and continuation_token; default 0.",
	"older_than_hours":   "Minimum age in hours since the upload was initiated, e.g. 72 or 0.5; default 24 (0 also means 24).",
	"object_lock":        "true creates the bucket with Object Lock (WORM retention) enabled; default false.",
	"status":             `"Enabled" or "Suspended" (case-sensitive). "Suspended" requires destructive approval.`,
	"cors_rules":         `Complete list of CORS rules using S3 field names, e.g. [{"AllowedOrigins": ["https://example.com"], "AllowedMethods": ["GET"], "AllowedHeaders": ["*"], "MaxAgeSeconds": 3600}]. Replaces all existing rules.`,
	"policy":             `Bucket policy document as a JSON string (not an object), e.g. "{\"Version\":\"2012-10-17\",\"Statement\":[...]}".`,
	"lock_configuration": `Object Lock configuration using S3 field names, e.g. {"ObjectLockEnabled": "Enabled", "Rule": {"DefaultRetention": {"Mode": "GOVERNANCE", "Days": 30}}}.`,

	"s3_create_bucket:bucket":                      `Name of the new bucket: 3-63 lowercase letters, digits, dots or hyphens, e.g. "backups-2026".`,
	"s3_copy_object:bucket":                        `Destination bucket name, e.g. "backups".`,
	"s3_copy_object:key":                           `Destination object key, e.g. "archive/2026/archive.tar".`,
	"s3_move_object:bucket":                        `Destination bucket name, e.g. "backups".`,
	"s3_move_object:key":                           `Destination object key, e.g. "archive/2026/archive.tar".`,
	"s3_create_folder:key":                         `Folder key, e.g. "reports/2026"; a trailing "/" is added when missing.`,
	"s3_delete_object:version_id":                  "Version to delete permanently; omit to delete the current object (only a bucket with versioning Enabled then keeps it recoverable behind a delete marker).",
	"s3_put_object_tagging:version_id":             "Version whose tags are replaced; omit for the current version.",
	"s3_multipart_create:key":                      `Object key the finished upload will create, e.g. "backups/disk.img".`,
	"s3_list_parts:continuation_token":             "Part-number marker: the continuation_token from the previous page; omit for the first page.",
	"s3_list_object_versions:continuation_token":   "Key marker: the continuation_token from the previous page, sent together with version_marker; omit for the first page.",
	"s3_list_multipart_uploads:continuation_token": "Key marker: the continuation_token from the previous page, sent together with upload_id; omit for the first page.",
	"s3_list_multipart_uploads:upload_id":          "Upload-ID marker: the upload_id_marker from the previous page, sent together with continuation_token; omit for the first page.",
	"s3_unfinished_uploads:continuation_token":     "Key marker from a previous partial result, sent together with upload_id to resume the scan; omit to start from the beginning.",
	"s3_unfinished_uploads:upload_id":              "Upload-ID marker: the upload_id_marker from a previous partial result, sent together with continuation_token; omit to start from the beginning.",
	"s3_unfinished_uploads:max_scan":               "Maximum number of multipart uploads to scan in this call; default 10000.",
	"s3_largest_objects:continuation_token":        "continuation_token from a previous partial result to scan the next batch of keys; omit to start at the beginning of prefix.",
	"s3_prefix_usage:continuation_token":           "continuation_token from a previous partial result to scan the next batch of keys; omit to start at the beginning of prefix.",
	"s3_prefix_usage:prefix":                       `Parent prefix whose first-level sub-prefixes are summed, e.g. "backups/"; omit for the bucket root.`,
	"s3_preview_object:max_bytes":                  "Number of leading bytes to read, 1-65536; default 65536.",
	"s3_preview_object:encoding":                   `"text" or "base64"; when omitted, text is used for valid UTF-8 and base64 otherwise.`,
	"s3_put_object:max_bytes":                      "Upper bound for the decoded data size, 1-262144 bytes; default 262144. Larger data is rejected before any request.",
	"s3_put_object:encoding":                       `How data is encoded: "text" (default, stored as UTF-8) or "base64" (decoded before upload, for binary content).`,
	"s3_presign_put:content_type":                  `MIME type the uploader must send as the Content-Type header, e.g. "image/png"; the signature covers it.`,
	"s3_download_file:path":                        `Destination file path relative to the configured file root, e.g. "restore/archive.tar"; absolute paths, ".." segments and symlinks leading outside are rejected.`,
	"s3_download_file:overwrite":                   "true replaces an existing local file at path and requires destructive approval; default false refuses an existing file.",
	"s3_upload_file:path":                          `Source file path relative to the configured file root, e.g. "exports/report.csv"; absolute paths, ".." segments and symlinks leading outside are rejected.`,
}

func paramDescription(tool, field string) string {
	if d, ok := paramDescriptions[tool+":"+field]; ok {
		return d
	}
	return paramDescriptions[field]
}
