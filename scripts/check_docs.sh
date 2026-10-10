#!/usr/bin/env bash
set -euo pipefail
kit="${S3_KIT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
profile="${S3_PROFILE:-internal/provider/profile.yaml}"
if [[ ! -f "$profile" ]]; then profile=internal/testprofile/profile.yaml; fi
binary=$(sed -n 's/^binary: //p' "$profile")
bash "$kit/scripts/go.sh" sh -c 'go build -o /tmp/provider-binary "./cmd/$1" && go run "/kit/scripts/check_docs.go" /tmp/provider-binary "$2" /kit/testdata/server.schema.json' sh "$binary" "$profile"
