#!/usr/bin/env bash
set -euo pipefail
kit="${S3_KIT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
bash "$kit/scripts/go.sh" sh -c 'go build ./... && go vet ./... && go vet -tags conformance ./... && go test -race -count=1 ./...'
docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp -e GOCACHE=/cache/build -e GOMODCACHE=/cache/mod -e GOLANGCI_LINT_CACHE=/cache/lint -v "$HOME/.cache/sel-s3-go:/cache" -v "$PWD:/src" -w /src golangci/golangci-lint:v2.14.0 golangci-lint run --build-tags conformance ./...
bash "$kit/scripts/conformance.sh"
bash "$kit/scripts/mcp_smoke.sh"
bash "$kit/scripts/mutation_gate.sh"
bash "$kit/scripts/go.sh" go test -count=1 /kit/scripts/mutation_gate.go /kit/scripts/mutation_gate_test.go
if [[ -f internal/provider/profile.yaml ]]; then
  bash "$kit/scripts/check_docs.sh"
  docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp -e GOCACHE=/cache/build -e GOMODCACHE=/cache/mod -v "$HOME/.cache/sel-s3-go:/cache" -v "$PWD:/src" -w /src goreleaser/goreleaser:v2.18.3 release --snapshot --clean
fi
docker run --rm -u "$(id -u):$(id -g)" -v "$PWD:/repo:ro" -w /repo rhysd/actionlint:1.7.12 -no-color
