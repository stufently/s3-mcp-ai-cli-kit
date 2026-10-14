#!/usr/bin/env bash
# Render catalog files into the provider repository that is the cwd.
# The kit root is the directory that contains this script. --check compares
# without writing and prints the paths that differ.
set -euo pipefail

if [ "$#" -gt 1 ]; then
  echo "usage: provider_scaffold.sh [--check]" >&2
  exit 2
fi

mode=apply
if [ "$#" -eq 1 ]; then
  if [ "$1" != "--check" ]; then
    echo "usage: provider_scaffold.sh [--check]" >&2
    exit 2
  fi
  mode=check
fi

kit=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
root=$PWD

if [ ! -f "$root/internal/provider/profile.yaml" ] || [ ! -f "$root/server.json" ]; then
  echo "provider_scaffold: run from a provider repository root" >&2
  exit 1
fi

exec python3 - "$kit" "$root" "$mode" <<'PY'
import json
import os
import re
import subprocess
import sys

kit, root, mode = sys.argv[1:]
allowed = re.compile(r"[A-Za-z0-9 ._,:/()-]+\Z")


def fail(msg):
    sys.exit("provider_scaffold: " + msg)


def profile_field(text, name):
    match = re.search(r"^%s:\s*(\S.*?)\s*$" % re.escape(name), text, re.M)
    if not match:
        fail("profile.yaml has no %s" % name)
    return match.group(1)


with open(os.path.join(root, "internal/provider/profile.yaml"), encoding="utf-8") as handle:
    profile = handle.read()

pid = profile_field(profile, "id")
binary = profile_field(profile, "binary")
prefix = profile_field(profile, "env_prefix")
pool = profile_field(profile, "default_pool")
display = profile_field(profile, "display_name")

with open(os.path.join(root, "server.json"), encoding="utf-8") as handle:
    server = json.load(handle)
description = server.get("description")
version = server.get("version")
if not isinstance(description, str) or description == "":
    fail("server.json description is empty")
if not isinstance(version, str) or version == "":
    fail("server.json version is empty")

repo = pid + "-s3-mcp-ai-cli"
server_name = "io.github.stufently/" + repo
values = {
    "ID": pid,
    "BINARY": binary,
    "ENV_PREFIX": prefix,
    "DEFAULT_POOL": pool,
    "DISPLAY_NAME": display,
    "REPO": repo,
    "SERVER_NAME": server_name,
    "DESCRIPTION": description,
}
for key, value in values.items():
    if allowed.fullmatch(value) is None:
        fail("%s contains characters outside [A-Za-z0-9 ._,:/()-]" % key)


def render(text):
    for key, value in values.items():
        text = text.replace("@@%s@@" % key, value)
    if "@@" in text:
        fail("unreplaced placeholder in a template")
    return text


files = {}
modes = {}


def add_text(rel, text, file_mode=None):
    if not text.endswith("\n"):
        text += "\n"
    files[rel] = text.encode("utf-8")
    modes[rel] = file_mode


template_map = (
    ("glama.json", "glama.json"),
    ("Dockerfile", "Dockerfile"),
    ("release.yml", ".github/workflows/release.yml"),
    ("mcpb/manifest.json", "mcpb/manifest.json"),
)
for src_rel, dest_rel in template_map:
    src = os.path.join(kit, "templates/provider", src_rel)
    with open(src, encoding="utf-8") as handle:
        add_text(dest_rel, render(handle.read()))

for name in ("build-mcpb.sh", "mcpb-checksums.sh"):
    src = os.path.join(kit, "scripts", name)
    with open(src, "rb") as handle:
        files["scripts/" + name] = handle.read()
    modes["scripts/" + name] = 0o755

identifier = "ghcr.io/stufently/%s:%s" % (repo, version)
jq = subprocess.run(
    [
        "jq",
        "--arg",
        "identifier",
        identifier,
        ".packages[0].identifier = $identifier | del(.packages[0].version)",
        os.path.join(root, "server.json"),
    ],
    check=False,
    capture_output=True,
    text=True,
)
if jq.returncode != 0:
    sys.stderr.write(jq.stderr)
    fail("jq could not normalize server.json")
files["server.json"] = jq.stdout.encode("utf-8")
modes["server.json"] = None


def with_ignore(rel, line):
    path = os.path.join(root, rel)
    if not os.path.isfile(path):
        fail("missing %s" % rel)
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    if any(token.strip("/") == "dist-mcpb" for token in text.split()):
        files[rel] = text.encode("utf-8")
    else:
        if text and not text.endswith("\n"):
            text += "\n"
        files[rel] = (text + line + "\n").encode("utf-8")
    modes[rel] = None


with_ignore(".gitignore", "/dist-mcpb/")
with_ignore(".dockerignore", "dist-mcpb")


def differs(rel):
    path = os.path.join(root, rel)
    if not os.path.isfile(path):
        return True
    with open(path, "rb") as handle:
        current = handle.read()
    if current != files[rel]:
        return True
    file_mode = modes[rel]
    if file_mode is not None and (os.stat(path).st_mode & 0o777) != file_mode:
        return True
    return False


diffs = [rel for rel in sorted(files) if differs(rel)]
if mode == "check":
    if diffs:
        for rel in diffs:
            print(rel)
        sys.exit(1)
    sys.exit(0)

for rel in sorted(files):
    path = os.path.join(root, rel)
    parent = os.path.dirname(path)
    if parent:
        os.makedirs(parent, exist_ok=True)
    current = b""
    if os.path.isfile(path):
        with open(path, "rb") as handle:
            current = handle.read()
    if current != files[rel]:
        with open(path, "wb") as handle:
            handle.write(files[rel])
    file_mode = modes[rel]
    if file_mode is not None:
        os.chmod(path, file_mode)
PY
