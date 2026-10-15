#!/usr/bin/env bash
# Run the provider-catalog cases that CI must keep green: scaffold render and
# --check, build-mcpb prechecks (no Docker), and catalog_check.py static.
# Each case prints one "ok <name>" or "FAIL <name>: <reason>" line.
set -uo pipefail

kit=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
scaffold=$kit/scripts/provider_scaffold.sh
checker=$kit/specs/checks/catalog_check.py
fixture=$kit/testdata/catalog-provider
export PYTHONDONTWRITEBYTECODE=1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail=0
cap_out=
cap_err=
cap_rc=0
dock_marker=
dock_home=
dock_bin=

new_repo() {
  local dir
  dir=$(mktemp -d "$work/repo.XXXXXX") || return 1
  cp -a "$fixture/." "$dir/" || return 1
  git -C "$dir" init -q >/dev/null || return 1
  printf '%s\n' "$dir"
}

capture() {
  local dir=$1
  shift
  cap_out=$(mktemp "$work/out.XXXXXX")
  cap_err=$(mktemp "$work/err.XXXXXX")
  cap_rc=0
  ( cd "$dir" && "$@" >"$cap_out" 2>"$cap_err" ) || cap_rc=$?
}

stderr_has_line() {
  local want=$1 line
  while IFS= read -r line || [[ -n $line ]]; do
    if [[ $line == "$want" ]]; then
      return 0
    fi
  done < "$cap_err"
  return 1
}

prepare_docker() {
  local bin
  bin=$(mktemp -d "$work/dock.XXXXXX")
  dock_marker=$bin/called
  dock_home=$(mktemp -d "$work/home.XXXXXX")
  dock_bin=$bin
  printf '#!/bin/sh\ntouch "%s"\nexit 97\n' "$dock_marker" > "$bin/docker"
  chmod +x "$bin/docker"
}

jq_edit() {
  local file=$1 filter=$2 tmp
  tmp=$(mktemp "$work/jq.XXXXXX")
  if ! jq "$filter" "$file" > "$tmp"; then
    printf 'jq failed on %s\n' "$file"
    return 1
  fi
  mv "$tmp" "$file"
}

require_render() {
  local dir=$1 script=$2
  capture "$dir" bash "$script"
  if [[ $cap_rc -ne 0 ]]; then
    printf 'render rc %s: %s\n' "$cap_rc" "$(cat "$cap_err")"
    return 1
  fi
}

tree_state() {
  ( cd "$1" && find . -path ./.git -prune -o -type f -printf '%m %p\n' | LC_ALL=C sort &&
    find . -path ./.git -prune -o -type f -exec sha256sum {} + | LC_ALL=C sort -k2 )
}

# --check must only report: the tree (contents and modes) stays as it was.
capture_check() {
  local dir=$1 before after
  before=$(tree_state "$dir") || { printf 'tree snapshot failed\n'; return 1; }
  capture "$dir" bash "$scaffold" --check
  after=$(tree_state "$dir") || { printf 'tree snapshot failed\n'; return 1; }
  if [[ $before != "$after" ]]; then
    printf -- '--check changed files or modes\n'
    return 1
  fi
}

require_check_exact() {
  local dir=$1 want=$2 got
  capture_check "$dir" || return 1
  if [[ $cap_rc -eq 0 ]]; then
    printf 'check succeeded, want drift in %s\n' "$want"
    return 1
  fi
  got=$(cat "$cap_out")
  if [[ $got != "$want" ]]; then
    printf 'check output %q, want %q\n' "$got" "$want"
    return 1
  fi
}

no_placeholders() {
  local root=$1 f st
  for f in \
    "$root/glama.json" \
    "$root/Dockerfile" \
    "$root/.github/workflows/release.yml" \
    "$root/mcpb/manifest.json" \
    "$root/scripts/build-mcpb.sh" \
    "$root/scripts/mcpb-checksums.sh" \
    "$root/server.json" \
    "$root/.gitignore" \
    "$root/.dockerignore"
  do
    if [[ ! -f $f ]]; then
      printf 'missing rendered file %s\n' "$f"
      return 1
    fi
    st=0
    grep -F -q -- '@@' "$f" || st=$?
    if [[ $st -eq 0 ]]; then
      printf 'unreplaced @@ in %s\n' "$f"
      return 1
    fi
    if [[ $st -gt 1 ]]; then
      printf 'grep failed on %s\n' "$f"
      return 1
    fi
  done
}

run_static() {
  local dir=$1
  capture "$dir" python3 -I "$checker" static "$dir"
}

require_static_fail() {
  local needle=$1
  if [[ $cap_rc -eq 0 ]]; then
    printf 'static succeeded\n'
    return 1
  fi
  if ! grep -F -q -- "$needle" "$cap_out" "$cap_err"; then
    printf 'static output missing %q: %s\n' "$needle" "$(cat "$cap_out" "$cap_err")"
    return 1
  fi
}

require_build_blocked() {
  local kind=$1 needle=$2
  if [[ -e $dock_marker ]]; then
    printf 'docker was called\n'
    return 1
  fi
  if [[ $cap_rc -eq 0 ]]; then
    printf 'build succeeded\n'
    return 1
  fi
  if [[ $kind == line ]]; then
    if ! stderr_has_line "$needle"; then
      printf 'stderr has no exact line %q: %s\n' "$needle" "$(cat "$cap_err")"
      return 1
    fi
  elif ! grep -F -q -- "$needle" "$cap_err"; then
    printf 'stderr missing %q: %s\n' "$needle" "$(cat "$cap_err")"
    return 1
  fi
}

case_render_clean() {
  local dir
  dir=$(new_repo) || { printf 'fixture copy failed\n'; return 1; }
  require_render "$dir" "$scaffold" || return 1
  capture_check "$dir" || return 1
  if [[ $cap_rc -ne 0 ]]; then
    printf 'check rc %s: %s\n' "$cap_rc" "$(cat "$cap_out" "$cap_err")"
    return 1
  fi
  run_static "$dir"
  if [[ $cap_rc -ne 0 ]]; then
    printf 'static rc %s: %s\n' "$cap_rc" "$(cat "$cap_out" "$cap_err")"
    return 1
  fi
  if [[ ! -x $dir/scripts/build-mcpb.sh || ! -x $dir/scripts/mcpb-checksums.sh ]]; then
    printf 'rendered scripts are not executable\n'
    return 1
  fi
  no_placeholders "$dir"
}

case_check_drift_release() {
  local dir
  dir=$(new_repo) || { printf 'fixture copy failed\n'; return 1; }
  require_render "$dir" "$scaffold" || return 1
  printf '\n# catalog-selftest-drift\n' >> "$dir/.github/workflows/release.yml"
  require_check_exact "$dir" '.github/workflows/release.yml'
}

case_check_drift_server_version() {
  local dir
  dir=$(new_repo) || { printf 'fixture copy failed\n'; return 1; }
  require_render "$dir" "$scaffold" || return 1
  jq_edit "$dir/server.json" '.packages[0].version = .version' || return 1
  require_check_exact "$dir" 'server.json'
}

case_check_exec_bit() {
  local dir
  dir=$(new_repo) || { printf 'fixture copy failed\n'; return 1; }
  require_render "$dir" "$scaffold" || return 1
  chmod 0644 "$dir/scripts/build-mcpb.sh"
  require_check_exact "$dir" 'scripts/build-mcpb.sh'
}

case_check_mode_0775() {
  local dir
  dir=$(new_repo) || { printf 'fixture copy failed\n'; return 1; }
  require_render "$dir" "$scaffold" || return 1
  chmod 0775 "$dir/scripts/build-mcpb.sh" "$dir/scripts/mcpb-checksums.sh"
  capture_check "$dir" || return 1
  if [[ $cap_rc -ne 0 ]]; then
    printf 'check rc %s: %s\n' "$cap_rc" "$(cat "$cap_out" "$cap_err")"
    return 1
  fi
}

case_reject_unsafe_value() {
  local dir
  dir=$(new_repo) || { printf 'fixture copy failed\n'; return 1; }
  python3 - "$dir/internal/provider/profile.yaml" <<'PY' || { printf 'could not edit display_name\n'; return 1; }
import sys
from pathlib import Path
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
old = "display_name: Selectel\n"
new = "display_name: Bad \"Name\"\n"
if text.count(old) != 1:
    raise SystemExit("display_name line not found once")
path.write_text(text.replace(old, new, 1), encoding="utf-8")
PY
  capture "$dir" bash "$scaffold"
  if [[ $cap_rc -eq 0 ]]; then
    printf 'render succeeded\n'
    return 1
  fi
  if ! grep -F -q -- 'DISPLAY_NAME' "$cap_err"; then
    printf 'stderr missing DISPLAY_NAME: %s\n' "$(cat "$cap_err")"
    return 1
  fi
  if [[ -e $dir/glama.json ]]; then
    printf 'glama.json was written\n'
    return 1
  fi
}

case_reject_placeholder() {
  local dir copy
  dir=$(new_repo) || { printf 'fixture copy failed\n'; return 1; }
  copy=$(mktemp -d "$work/kit.XXXXXX")
  cp -a "$kit/scripts" "$kit/templates" "$copy/"
  printf '\n@@UNKNOWN@@\n' >> "$copy/templates/provider/glama.json"
  capture "$dir" bash "$copy/scripts/provider_scaffold.sh"
  if [[ $cap_rc -eq 0 ]]; then
    printf 'render succeeded\n'
    return 1
  fi
  if ! grep -F -q -- 'unreplaced placeholder' "$cap_err"; then
    printf 'stderr missing unreplaced placeholder: %s\n' "$(cat "$cap_err")"
    return 1
  fi
  if [[ -e $dir/glama.json ]]; then
    printf 'glama.json was written\n'
    return 1
  fi
}

case_commented_ignore() {
  local dir src
  dir=$(new_repo) || { printf 'fixture copy failed\n'; return 1; }
  printf '%s\n' '# dist-mcpb' > "$dir/.gitignore"
  require_render "$dir" "$scaffold" || return 1
  # A global excludes file must not stand in for the rendered .gitignore rule.
  if ! src=$(cd "$dir" && git -c core.excludesFile=/dev/null check-ignore -v dist-mcpb/probe); then
    printf 'dist-mcpb/probe is not ignored\n'
    return 1
  fi
  if [[ $src != .gitignore:* ]]; then
    printf 'dist-mcpb/probe ignored by %s, not .gitignore\n' "$src"
    return 1
  fi
}

build_env() {
  local dir=$1
  shift
  prepare_docker
  capture "$dir" env HOME="$dock_home" PATH="$dock_bin:$PATH" "$@" bash scripts/build-mcpb.sh
}

case_build_no_version() {
  local dir
  dir=$(new_repo) || { printf 'fixture copy failed\n'; return 1; }
  require_render "$dir" "$scaffold" || return 1
  build_env "$dir" env -u VERSION
  require_build_blocked line 'VERSION is required'
}

case_build_unsafe_version() {
  local dir
  dir=$(new_repo) || { printf 'fixture copy failed\n'; return 1; }
  require_render "$dir" "$scaffold" || return 1
  build_env "$dir" VERSION='1;touch x'
  require_build_blocked substr 'not a safe version token' || return 1
  if [[ -e $dir/x ]]; then
    printf 'file x was created\n'
    return 1
  fi
}

case_build_missing_golden() {
  local dir
  dir=$(new_repo) || { printf 'fixture copy failed\n'; return 1; }
  require_render "$dir" "$scaffold" || return 1
  rm -f "$dir/testdata/tools/all.golden"
  build_env "$dir" VERSION=0.0.1
  require_build_blocked substr 'all.golden'
}

case_build_missing_default() {
  local dir found
  dir=$(new_repo) || { printf 'fixture copy failed\n'; return 1; }
  require_render "$dir" "$scaffold" || return 1
  jq_edit "$dir/mcpb/manifest.json" 'del(.user_config.endpoint.default)' || return 1
  build_env "$dir" VERSION=0.0.1
  require_build_blocked line 'endpoint' || return 1
  found=$(find "$dir" -name '*.mcpb' -print -quit)
  if [[ -n $found ]]; then
    printf 'mcpb bundle was written: %s\n' "$found"
    return 1
  fi
}

case_build_reaches_docker() {
  local dir
  dir=$(new_repo) || { printf 'fixture copy failed\n'; return 1; }
  require_render "$dir" "$scaffold" || return 1
  build_env "$dir" VERSION=0.0.1
  if [[ ! -e $dock_marker ]]; then
    printf 'docker stub was not called (rc %s): %s\n' "$cap_rc" "$(cat "$cap_err")"
    return 1
  fi
}

case_static_package_version() {
  local dir
  dir=$(new_repo) || { printf 'fixture copy failed\n'; return 1; }
  require_render "$dir" "$scaffold" || return 1
  jq_edit "$dir/server.json" '.packages[0].version = .version' || return 1
  run_static "$dir"
  require_static_fail 'OCI package must not have version'
}

case_static_identifier() {
  local dir
  dir=$(new_repo) || { printf 'fixture copy failed\n'; return 1; }
  require_render "$dir" "$scaffold" || return 1
  jq_edit "$dir/server.json" '.packages[0].identifier |= sub(":[^:]*$"; "")' || return 1
  run_static "$dir"
  require_static_fail 'OCI identifier must be'
}

case_static_label() {
  local dir tmp st
  dir=$(new_repo) || { printf 'fixture copy failed\n'; return 1; }
  require_render "$dir" "$scaffold" || return 1
  st=0
  grep -F -q -- 'io.modelcontextprotocol.server.name' "$dir/Dockerfile" || st=$?
  if [[ $st -ne 0 ]]; then
    printf 'Dockerfile has no server.name label\n'
    return 1
  fi
  tmp=$(mktemp "$work/df.XXXXXX")
  grep -v 'io.modelcontextprotocol.server.name' "$dir/Dockerfile" > "$tmp"
  mv "$tmp" "$dir/Dockerfile"
  run_static "$dir"
  require_static_fail 'io.modelcontextprotocol.server.name'
}

case_static_endpoint_default() {
  local dir
  dir=$(new_repo) || { printf 'fixture copy failed\n'; return 1; }
  require_render "$dir" "$scaffold" || return 1
  jq_edit "$dir/mcpb/manifest.json" '.user_config.endpoint.default = "https://wrong.invalid"' || return 1
  run_static "$dir"
  require_static_fail 'user_config.endpoint default must be'
}

case_static_extra_job() {
  local dir
  dir=$(new_repo) || { printf 'fixture copy failed\n'; return 1; }
  require_render "$dir" "$scaffold" || return 1
  printf '\n  unexpected:\n    runs-on: ubuntu-latest\n' >> "$dir/.github/workflows/release.yml"
  run_static "$dir"
  require_static_fail 'jobs must be exactly'
}

case_static_license() {
  local dir
  dir=$(new_repo) || { printf 'fixture copy failed\n'; return 1; }
  require_render "$dir" "$scaffold" || return 1
  jq_edit "$dir/mcpb/manifest.json" '.license = "Apache-2.0"' || return 1
  run_static "$dir"
  require_static_fail 'manifest license must be MIT'
}

case_static_transport() {
  local dir
  dir=$(new_repo) || { printf 'fixture copy failed\n'; return 1; }
  require_render "$dir" "$scaffold" || return 1
  jq_edit "$dir/server.json" '.packages[0].transport = {"type":"streamable-http"}' || return 1
  run_static "$dir"
  require_static_fail 'transport stdio'
}

case_static_exec_bit() {
  local dir
  dir=$(new_repo) || { printf 'fixture copy failed\n'; return 1; }
  require_render "$dir" "$scaffold" || return 1
  chmod 0644 "$dir/scripts/build-mcpb.sh"
  run_static "$dir"
  require_static_fail 'scripts/build-mcpb.sh must exist and be executable'
}

# Body of "Check the tag against server.json". Its run: | lines are indented
# by 10 spaces. A missing step is an error so the case cannot pass vacuously.
release_tag_body() {
  local yml=$1
  awk '
    /^[[:space:]]*- name: Check the tag against server.json$/ { found = 1; next }
    found && /^[[:space:]]*run: \|$/ { grab = 1; next }
    found && grab {
      if (substr($0, 1, 10) == "          ") {
        print substr($0, 11)
        next
      }
      exit
    }
    END { if (!grab) exit 1 }
  ' "$yml"
}

case_check_exec_bit_checksums() {
  local dir
  dir=$(new_repo) || { printf 'fixture copy failed\n'; return 1; }
  require_render "$dir" "$scaffold" || return 1
  chmod 0644 "$dir/scripts/mcpb-checksums.sh"
  require_check_exact "$dir" 'scripts/mcpb-checksums.sh'
}

case_render_description() {
  local dir desc want
  dir=$(new_repo) || { printf 'fixture copy failed\n'; return 1; }
  require_render "$dir" "$scaffold" || return 1
  desc=$(jq -r '.description // empty' "$dir/mcpb/manifest.json") || {
    printf 'could not read manifest description\n'
    return 1
  }
  want=$(jq -r '.description // empty' "$dir/server.json") || {
    printf 'could not read server description\n'
    return 1
  }
  if [[ -z $desc ]]; then
    printf 'manifest description is missing or empty\n'
    return 1
  fi
  if [[ $desc != "$want" ]]; then
    printf 'manifest description %q, want %q\n' "$desc" "$want"
    return 1
  fi
}

case_release_tag_mismatch() {
  local dir version body
  dir=$(new_repo) || { printf 'fixture copy failed\n'; return 1; }
  require_render "$dir" "$scaffold" || return 1
  version=$(jq -r '.version // empty' "$dir/server.json") || {
    printf 'could not read server.json version\n'
    return 1
  }
  if [[ -z $version || $version == null ]]; then
    printf 'server.json version is empty\n'
    return 1
  fi
  body=$(release_tag_body "$dir/.github/workflows/release.yml") || {
    printf 'release tag step not found\n'
    return 1
  }
  if [[ -z $body ]]; then
    printf 'release tag step not found\n'
    return 1
  fi
  capture "$dir" env "GITHUB_REF_NAME=v${version}" bash -c "$body"
  if [[ $cap_rc -ne 0 ]]; then
    printf 'matching tag rc %s: %s\n' "$cap_rc" "$(cat "$cap_err")"
    return 1
  fi
  capture "$dir" env GITHUB_REF_NAME=v9.9.9 bash -c "$body"
  if [[ $cap_rc -eq 0 ]]; then
    printf 'mismatched tag succeeded\n'
    return 1
  fi
  if ! grep -F -q -- 'does not match server.json' "$cap_err"; then
    printf 'stderr missing does not match server.json: %s\n' "$(cat "$cap_err")"
    return 1
  fi
}

case_build_unsafe_binary() {
  local dir
  dir=$(new_repo) || { printf 'fixture copy failed\n'; return 1; }
  require_render "$dir" "$scaffold" || return 1
  python3 - "$dir/internal/provider/profile.yaml" <<'PY' || { printf 'could not edit binary\n'; return 1; }
import sys
from pathlib import Path
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
old = "binary: selectel-s3\n"
new = "binary: bad/name\n"
if text.count(old) != 1:
    raise SystemExit("binary line not found once")
path.write_text(text.replace(old, new, 1), encoding="utf-8")
PY
  build_env "$dir" VERSION=0.0.1
  require_build_blocked substr 'binary is not a safe token'
}

case_build_missing_pool_default() {
  local dir found
  dir=$(new_repo) || { printf 'fixture copy failed\n'; return 1; }
  require_render "$dir" "$scaffold" || return 1
  jq_edit "$dir/mcpb/manifest.json" 'del(.user_config.pool.default)' || return 1
  build_env "$dir" VERSION=0.0.1
  require_build_blocked line 'pool' || return 1
  found=$(find "$dir" -name '*.mcpb' -print -quit)
  if [[ -n $found ]]; then
    printf 'mcpb bundle was written: %s\n' "$found"
    return 1
  fi
}

case_checksums_keep_archive() {
  local dir a1 a2 stale n
  dir=$(mktemp -d "$work/sums.XXXXXX") || { printf 'temp dir failed\n'; return 1; }
  mkdir -p "$dir/bundles"
  printf 'bundle-a\n' > "$dir/bundles/a.mcpb"
  a1='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa  z.tar.gz'
  a2='bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb  a.tar.gz'
  stale='cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc  a.mcpb'
  printf '%s\n' "$a1" "$a2" "$stale" > "$dir/checksums.txt"
  capture "$dir" bash "$kit/scripts/mcpb-checksums.sh" bundles checksums.txt
  if [[ $cap_rc -ne 0 ]]; then
    printf 'checksums rc %s: %s\n' "$cap_rc" "$(cat "$cap_err")"
    return 1
  fi
  printf '%s\n' "$a1" "$a2" > "$dir/want-prefix"
  head -n 2 "$dir/checksums.txt" > "$dir/got-prefix" || {
    printf 'could not read checksums.txt\n'
    return 1
  }
  if ! cmp -s "$dir/want-prefix" "$dir/got-prefix"; then
    printf 'archive lines were not kept in order\n'
    return 1
  fi
  n=$(wc -l < "$dir/checksums.txt")
  if [[ $n -ne 3 ]]; then
    printf 'checksums.txt has %s lines, want 3\n' "$n"
    return 1
  fi
}

case_checksums_bundle_hash() {
  local dir want
  dir=$(mktemp -d "$work/sums.XXXXXX") || { printf 'temp dir failed\n'; return 1; }
  mkdir -p "$dir/bundles"
  printf 'alpha\n' > "$dir/bundles/a.mcpb"
  printf 'beta\n' > "$dir/bundles/b.mcpb"
  capture "$dir" bash "$kit/scripts/mcpb-checksums.sh" bundles checksums.txt
  if [[ $cap_rc -ne 0 ]]; then
    printf 'checksums rc %s: %s\n' "$cap_rc" "$(cat "$cap_err")"
    return 1
  fi
  want=$(mktemp "$work/want.XXXXXX")
  ( cd "$dir/bundles" && sha256sum a.mcpb b.mcpb > "$want" ) || {
    printf 'sha256sum failed\n'
    return 1
  }
  if ! cmp -s "$dir/checksums.txt" "$want"; then
    printf 'checksums.txt differs from sha256sum of the bundles\n'
    return 1
  fi
}

# Run the rendered tag step with GITHUB_REF_NAME=$2 after setting the first
# package identifier in server.json to $3. Only one of the two compared pairs
# differs, so an "and" in place of the "or" lets the release through.
release_tag_one_side() {
  local dir=$1 tag=$2 ident=$3 body
  jq_edit "$dir/server.json" ".packages[0].identifier = \"$ident\"" || return 1
  body=$(release_tag_body "$dir/.github/workflows/release.yml") || {
    printf 'release tag step not found\n'
    return 1
  }
  if [[ -z $body ]]; then
    printf 'release tag step not found\n'
    return 1
  fi
  capture "$dir" env "GITHUB_REF_NAME=$tag" bash -c "$body"
  if [[ $cap_rc -eq 0 ]]; then
    printf 'tag %s with identifier %s succeeded\n' "$tag" "$ident"
    return 1
  fi
  if ! grep -F -q -- 'does not match server.json' "$cap_err"; then
    printf 'stderr missing does not match server.json: %s\n' "$(cat "$cap_err")"
    return 1
  fi
}

case_release_tag_one_side() {
  local dir version ident
  dir=$(new_repo) || { printf 'fixture copy failed\n'; return 1; }
  require_render "$dir" "$scaffold" || return 1
  version=$(jq -r '.version // empty' "$dir/server.json") || {
    printf 'could not read server.json version\n'
    return 1
  }
  ident=$(jq -r '.packages[0].identifier // empty' "$dir/server.json") || {
    printf 'could not read server.json identifier\n'
    return 1
  }
  if [[ -z $version || $ident != *":$version" ]]; then
    printf 'unexpected server.json version %q or identifier %q\n' "$version" "$ident"
    return 1
  fi
  # Version matches the tag, identifier names another image.
  release_tag_one_side "$dir" "v$version" "ghcr.io/stufently/other-image:$version" || return 1
  # Identifier matches the tag, version does not.
  release_tag_one_side "$dir" v9.9.9 "${ident%:*}:9.9.9"
}

# The registry job must publish plain tags and skip prereleases (v1.2.3-rc.1).
# The job's if: is evaluated for both refs; an expression outside the small
# grammar below is a failure, never a pass.
case_registry_skips_prerelease() {
  local dir
  dir=$(new_repo) || { printf 'fixture copy failed\n'; return 1; }
  require_render "$dir" "$scaffold" || return 1
  capture "$dir" python3 -I - .github/workflows/release.yml <<'PY'
import re
import sys

lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
start = None
for i, line in enumerate(lines):
    if line == "  registry:":
        start = i
        break
if start is None:
    sys.exit("registry job not found")
expr = None
for line in lines[start + 1:]:
    if line.startswith("  ") and not line.startswith("    ") and line.strip():
        break
    m = re.match(r"^    if: (.*)$", line)
    if m:
        expr = m.group(1).strip()
if expr is None:
    sys.exit("registry job has no if:")
m = re.fullmatch(r"\$\{\{(.*)\}\}", expr)
if m:
    expr = m.group(1)
tokens = re.findall(r"\s*(&&|\|\||!|\(|\)|,|'[^']*'|[A-Za-z_][A-Za-z0-9_.]*)", expr)
if "".join(tokens).replace(" ", "") != expr.replace(" ", ""):
    sys.exit("unsupported if: expression %r" % expr)
tokens = [t.strip() for t in tokens]


def evaluate(ref):
    pos = 0

    def peek():
        return tokens[pos] if pos < len(tokens) else None

    def take(want=None):
        nonlocal pos
        tok = peek()
        if tok is None or (want is not None and tok != want):
            raise ValueError("expected %r, got %r" % (want, tok))
        pos += 1
        return tok

    def value():
        tok = take()
        if tok == "github.ref_name":
            return ref
        if tok.startswith("'"):
            return tok[1:-1]
        raise ValueError("unsupported operand %r" % tok)

    def unary():
        tok = peek()
        if tok == "!":
            take()
            return not unary()
        if tok == "(":
            take()
            got = disj()
            take(")")
            return got
        if tok in ("contains", "startsWith", "endsWith"):
            take()
            take("(")
            a = value()
            take(",")
            b = value()
            take(")")
            return {"contains": b in a, "startsWith": a.startswith(b), "endsWith": a.endswith(b)}[tok]
        raise ValueError("unsupported token %r" % tok)

    def conj():
        got = unary()
        while peek() == "&&":
            take()
            right = unary()
            got = got and right
        return got

    def disj():
        got = conj()
        while peek() == "||":
            take()
            right = conj()
            got = got or right
        return got

    got = disj()
    if pos != len(tokens):
        raise ValueError("trailing tokens in %r" % expr)
    return got


try:
    plain = evaluate("v1.2.3")
    pre = evaluate("v1.2.3-rc.1")
except ValueError as exc:
    sys.exit("cannot evaluate registry if: %s" % exc)
if plain is not True:
    sys.exit("registry job skips plain tag v1.2.3")
if pre is not False:
    sys.exit("registry job runs for prerelease v1.2.3-rc.1")
PY
  if [[ $cap_rc -ne 0 ]]; then
    printf '%s\n' "$(cat "$cap_err")"
    return 1
  fi
}

case_build_unsafe_env_prefix() {
  local dir
  dir=$(new_repo) || { printf 'fixture copy failed\n'; return 1; }
  require_render "$dir" "$scaffold" || return 1
  python3 - "$dir/internal/provider/profile.yaml" <<'PY' || { printf 'could not edit env_prefix\n'; return 1; }
import sys
from pathlib import Path
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
old = "env_prefix: SELECTEL_S3_\n"
new = "env_prefix: BAD;touch x;\n"
if text.count(old) != 1:
    raise SystemExit("env_prefix line not found once")
path.write_text(text.replace(old, new, 1), encoding="utf-8")
PY
  build_env "$dir" VERSION=0.0.1
  require_build_blocked substr 'env_prefix is not a safe token'
}

# A sha256sum that writes wrong sums but checks honestly: the self-check must
# refuse, and the published checksums.txt must stay byte for byte as it was.
case_checksums_verify_first() {
  local dir real bin a1 left
  dir=$(mktemp -d "$work/sums.XXXXXX") || { printf 'temp dir failed\n'; return 1; }
  real=$(command -v sha256sum) || { printf 'sha256sum not found\n'; return 1; }
  bin=$dir/bin
  mkdir -p "$dir/bundles" "$bin"
  printf 'alpha\n' > "$dir/bundles/a.mcpb"
  cat > "$bin/sha256sum" <<EOF
#!/bin/sh
for arg in "\$@"; do
  if [ "\$arg" = -c ]; then
    exec "$real" "\$@"
  fi
done
"$real" "\$@" | sed 's/^[0-9a-f]\{64\}/0000000000000000000000000000000000000000000000000000000000000000/'
EOF
  chmod +x "$bin/sha256sum"
  a1='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa  z.tar.gz'
  printf '%s\n' "$a1" > "$dir/checksums.txt"
  cp "$dir/checksums.txt" "$dir/want"
  capture "$dir" env PATH="$bin:$PATH" bash "$kit/scripts/mcpb-checksums.sh" bundles checksums.txt
  if [[ $cap_rc -eq 0 ]]; then
    printf 'wrong bundle sums were published\n'
    return 1
  fi
  if ! grep -F -q -- 'sha256sum -c failed' "$cap_err"; then
    printf 'stderr missing sha256sum -c failed: %s\n' "$(cat "$cap_err")"
    return 1
  fi
  if ! cmp -s "$dir/want" "$dir/checksums.txt"; then
    printf 'checksums.txt changed after a failed check\n'
    return 1
  fi
  left=$(find "$dir" -maxdepth 1 -name '.mcpb-checksums.*' -print -quit)
  if [[ -n $left ]]; then
    printf 'temporary file left behind: %s\n' "$left"
    return 1
  fi
}

# The runtime stage of the rendered Dockerfile must end on a non-root USER.
case_static_nonroot_user() {
  local dir
  dir=$(new_repo) || { printf 'fixture copy failed\n'; return 1; }
  require_render "$dir" "$scaffold" || return 1
  capture "$dir" python3 -I - Dockerfile <<'PY'
import re
import sys

user = None
for line in open(sys.argv[1], encoding="utf-8"):
    word = line.split()
    if not word:
        continue
    if word[0].upper() == "FROM":
        user = None
    elif word[0].upper() == "USER":
        user = line.split(None, 1)[1].strip() if len(word) > 1 else ""
if user is None:
    sys.exit("runtime stage has no USER")
name = user.split(":", 1)[0]
if name in ("", "0", "root") or not re.fullmatch(r"[0-9]+", name):
    sys.exit("runtime stage runs as %r, want a numeric non-root uid" % user)
PY
  if [[ $cap_rc -ne 0 ]]; then
    printf '%s\n' "$(cat "$cap_err")"
    return 1
  fi
}

run_named() {
  case $1 in
    render-clean) case_render_clean ;;
    check-drift-release) case_check_drift_release ;;
    check-drift-server-version) case_check_drift_server_version ;;
    check-exec-bit) case_check_exec_bit ;;
    check-mode-0775) case_check_mode_0775 ;;
    reject-unsafe-value) case_reject_unsafe_value ;;
    reject-placeholder) case_reject_placeholder ;;
    commented-ignore) case_commented_ignore ;;
    build-no-version) case_build_no_version ;;
    build-unsafe-version) case_build_unsafe_version ;;
    build-missing-golden) case_build_missing_golden ;;
    build-missing-default) case_build_missing_default ;;
    build-reaches-docker) case_build_reaches_docker ;;
    static-package-version) case_static_package_version ;;
    static-identifier) case_static_identifier ;;
    static-label) case_static_label ;;
    static-endpoint-default) case_static_endpoint_default ;;
    static-extra-job) case_static_extra_job ;;
    static-license) case_static_license ;;
    static-transport) case_static_transport ;;
    static-exec-bit) case_static_exec_bit ;;
    check-exec-bit-checksums) case_check_exec_bit_checksums ;;
    render-description) case_render_description ;;
    release-tag-mismatch) case_release_tag_mismatch ;;
    build-unsafe-binary) case_build_unsafe_binary ;;
    build-missing-pool-default) case_build_missing_pool_default ;;
    checksums-keep-archive) case_checksums_keep_archive ;;
    checksums-bundle-hash) case_checksums_bundle_hash ;;
    release-tag-one-side) case_release_tag_one_side ;;
    registry-skips-prerelease) case_registry_skips_prerelease ;;
    build-unsafe-env-prefix) case_build_unsafe_env_prefix ;;
    checksums-verify-first) case_checksums_verify_first ;;
    static-nonroot-user) case_static_nonroot_user ;;
    *) printf 'unknown case %s\n' "$1"; return 1 ;;
  esac
}

run_case() {
  local name=$1 msg
  if msg=$(trap - EXIT; run_named "$name"); then
    printf 'ok %s\n' "$name"
  else
    msg=${msg//$'\n'/'; '}
    printf 'FAIL %s: %s\n' "$name" "$msg"
    fail=1
  fi
}

names=(
  render-clean
  check-drift-release
  check-drift-server-version
  check-exec-bit
  check-mode-0775
  reject-unsafe-value
  reject-placeholder
  commented-ignore
  build-no-version
  build-unsafe-version
  build-missing-golden
  build-missing-default
  build-reaches-docker
  static-package-version
  static-identifier
  static-label
  static-endpoint-default
  static-extra-job
  static-license
  static-transport
  static-exec-bit
  check-exec-bit-checksums
  render-description
  release-tag-mismatch
  build-unsafe-binary
  build-missing-pool-default
  checksums-keep-archive
  checksums-bundle-hash
  release-tag-one-side
  registry-skips-prerelease
  build-unsafe-env-prefix
  checksums-verify-first
  static-nonroot-user
)

for name in "${names[@]}"; do
  run_case "$name"
done

exit "$fail"
