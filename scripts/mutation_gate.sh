#!/usr/bin/env bash
set -euo pipefail
kit="${S3_KIT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
bash "$kit/scripts/go.sh" sh -c 'mkdir /tmp/kit-gate && cp -R /kit/. /tmp/kit-gate/ && cd /tmp/kit-gate && go build -o /tmp/mutation-gate scripts/mutation_gate.go && exec /tmp/mutation-gate'
