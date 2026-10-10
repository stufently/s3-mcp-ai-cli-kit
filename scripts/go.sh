#!/usr/bin/env bash
set -euo pipefail
kit="${S3_KIT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
mkdir -p "$HOME/.cache/sel-s3-go"
docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp -e GOCACHE=/cache/build -e GOMODCACHE=/cache/mod -e S3_KIT_ROOT=/kit -v "$HOME/.cache/sel-s3-go:/cache" -v "$kit:/kit:ro" -v "$PWD:/src" -w /src golang:1.27.2 "$@"
