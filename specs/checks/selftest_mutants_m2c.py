#!/usr/bin/env python3
"""Mutation probe for scripts/catalog_selftest.sh (milestone catalog-m2c).

Written by the coordinator, not by the executor. Stdlib only, run with python3 -I.

  selftest_mutants.py <kit_dir>

Milestone 2a probe (selftest_mutants.py) plus the seven mutants that survived its
acceptance run (N01, N02, N04, N05, N06, N08, N09): 34 mutants over six files.

Clones the COMMITTED HEAD of <kit_dir> into a temporary directory, checks that the
six mutation targets are byte-identical to the milestone base, runs the self-test
on the clean copy (every case must print "ok <case>", rc 0, tree stays clean), then
applies each mutant one at a time and requires the self-test to fail with a
"FAIL <case>" line for one of the cases expected to catch that mutant.
Exit 0 means every mutant was killed by its own case.
"""
import hashlib
import os
import re
import subprocess
import sys
import tempfile

TARGETS = {
    "A": "scripts/provider_scaffold.sh",
    "B": "scripts/build-mcpb.sh",
    "C": "specs/checks/catalog_check.py",
    "D": "scripts/mcpb-checksums.sh",
    "E": "templates/provider/release.yml",
    "F": "templates/provider/mcpb/manifest.json",
}
PINNED = {
    "scripts/provider_scaffold.sh": "650cd73907c224121e74c5088f3af9d87bbac0492a1550ee50ed2586e5f1c6ef",
    "scripts/build-mcpb.sh": "1978c5d4b1b12cf4af35915a299133428e2a2fb25647d451bd1e87a9ca2c8cde",
    "specs/checks/catalog_check.py": "147e0e9e0f8dbced0f1d23bdf36c1cdff4c689144ae6231086d7d010f601fd5b",
    "scripts/mcpb-checksums.sh": "8d6b1b8bb3aad65826f9b6a6078d578168ed0b109c8eac773b61a88f53e1e904",
    "templates/provider/release.yml": "88e97cb4508482b2ca59cfb3cf5af4a224b593d6123e83973c625b65856b1107",
    "templates/provider/mcpb/manifest.json": "5ca77f3336da1fe5933a7048b4582eec81f17839f7230c43bcf01323b9e9cf5f",
}
CASES = [
    "render-clean", "check-drift-release", "check-drift-server-version", "check-exec-bit",
    "check-mode-0775", "reject-unsafe-value", "reject-placeholder", "commented-ignore",
    "build-no-version", "build-unsafe-version", "build-missing-golden", "build-missing-default",
    "build-reaches-docker", "static-package-version", "static-identifier", "static-label",
    "static-endpoint-default", "static-extra-job", "static-license", "static-transport",
    "static-exec-bit", "check-exec-bit-checksums", "render-description", "release-tag-mismatch",
    "build-unsafe-binary", "build-missing-pool-default", "checksums-keep-archive",
    "checksums-bundle-hash",
]
TIMEOUT = 600

MUTANTS = []


def add(mid, old, new, cases, group=None):
    group = group or mid[0]
    MUTANTS.append((mid, group, TARGETS[group], old, new, cases))


add("A1", "if file_mode is not None and not os.stat(path).st_mode & 0o100:", "if False:",
    ["check-exec-bit"])
add("A2", ".packages[0].identifier = $identifier | del(.packages[0].version)",
    ".packages[0].identifier = $identifier", ["render-clean", "check-drift-server-version"])
add("A3", 'allowed = re.compile(r"[A-Za-z0-9 ._,:/()-]+\\Z")', 'allowed = re.compile(r".+\\Z")',
    ["reject-unsafe-value"])
add("A4", "            print(rel)\n        sys.exit(1)", "            print(rel)\n        sys.exit(0)",
    ["check-drift-release", "check-drift-server-version", "check-exec-bit"])
add("A5", 'with_ignore(".gitignore", "/dist-mcpb/")', "pass  # mutant", ["render-clean", "commented-ignore"])
add("A6", 'with_ignore(".dockerignore", "dist-mcpb")', "pass  # mutant", ["render-clean"])
add("A7", "[rel for rel in sorted(files) if differs(rel)]",
    '[rel for rel in sorted(files) if rel != "server.json" and differs(rel)]',
    ["check-drift-server-version"])
add("A8", '    ("glama.json", "glama.json"),\n', "", ["render-clean"])
add("A9", '    if "@@" in text:\n        fail("unreplaced placeholder in a template")',
    '    if False:\n        fail("unreplaced placeholder in a template")', ["reject-placeholder"])
add("A10", "if file_mode is not None and not os.stat(path).st_mode & 0o100:",
    "if file_mode is not None and os.stat(path).st_mode & 0o777 != 0o755:", ["check-mode-0775"])
add("A12", 'if any(rule.strip("/") == "dist-mcpb" for rule in rules if not rule.startswith("#")):',
    'if any(rule.lstrip("# ").strip("/") == "dist-mcpb" for rule in rules):', ["commented-ignore"])
add("A13", "        os.chmod(path, file_mode)", "        pass  # mutant", ["render-clean"])

add("B1", 'if [ -z "${VERSION:-}" ]; then\n  echo "VERSION is required" >&2\n  exit 1\nfi\n', "",
    ["build-no-version"])
add("B2", "'^[0-9A-Za-z][0-9A-Za-z._+-]*$'", "'^.+$'", ["build-unsafe-version"])
add("B3", 'opt.get("required") is not True', 'opt.get("required")', ["build-reaches-docker"])
add("B4", "        print(name, file=sys.stderr)\n    sys.exit(1)", "        print(name, file=sys.stderr)\n    pass",
    ["build-missing-default"])
add("B5", None, None, ["build-missing-default"])  # validation block moved after the Docker build
add("B6", "print(name, file=sys.stderr)", 'print("missing default", file=sys.stderr)',
    ["build-missing-default"])
add("B7", 'if [ ! -f "$profile" ] || [ ! -f mcpb/manifest.json ] || [ ! -f testdata/tools/all.golden ]; then',
    "if false; then", ["build-missing-golden"])

add("C1", 'check("version" not in p0,', "check(True,", ["static-package-version"])
add("C2", 'check(p0.get("identifier") == "ghcr.io/stufently/%s:%s" % (f["repo"], s.get("version")),',
    "check(True,", ["static-identifier"])
add("C3", "check(re.search(r'io\\.modelcontextprotocol\\.server\\.name=\"%s\"' % re.escape(f[\"name\"]), last) is not None,",
    "check(True,", ["static-label"])
add("C4", 'check(o.get("default") == d,', "check(True,", ["static-endpoint-default"])
add("C5", 'check(set(jobs) == {"goreleaser", "image", "mcpb", "registry"},', "check(True,", ["static-extra-job"])
add("C6", 'check(m.get("license") == "MIT",', "check(True,", ["static-license"])
add("C7", 'check(p0.get("transport") == {"type": "stdio"},', "check(True,", ["static-transport"])
add("C8", "check(os.path.isfile(path) and os.access(path, os.X_OK),", "check(os.path.isfile(path),",
    ["static-exec-bit"])


# Survivors of the 2a acceptance mutation run (Codex, 14.10.2026), exact edits.
add("N01", "if ! printf '%s\\n' \"$binary\" | grep -Eq '^[A-Za-z0-9_-]+$'; then\n"
    "  echo \"build-mcpb: binary is not a safe token\" >&2\n  exit 1\nfi\n", "",
    ["build-unsafe-binary"], "B")
add("N02", "for name, opt in user_config.items():",
    "for name, opt in user_config.items():\n    if name != \"endpoint\":\n        continue",
    ["build-missing-pool-default"], "B")
add("N04", "    file_mode = modes[rel]\n    # Git tracks only the executable bit;",
    "    file_mode = modes[rel] if rel != \"scripts/mcpb-checksums.sh\" else None\n"
    "    # Git tracks only the executable bit;", ["check-exec-bit-checksums"], "A")
add("N05", "if [ -f \"$sums\" ]; then\n  while IFS=", "if false; then\n  while IFS=",
    ["checksums-keep-archive"], "D")
add("N06", "  sha256sum -- \"${names[@]}\"", "  sha256sum -- /dev/null", ["checksums-bundle-hash"], "D")
add("N08", "          if [ \"$version\" != \"$got\" ] || [ \"$id\" != \"$want\" ]; then",
    "          if false; then", ["release-tag-mismatch"], "E")
add("N09", "  \"description\": \"@@DESCRIPTION@@\",\n", "", ["render-description"], "F")


def run(args, cwd, timeout=TIMEOUT):
    env = dict(os.environ)
    env.pop("VERSION", None)
    return subprocess.run(args, cwd=cwd, env=env, capture_output=True, text=True, timeout=timeout)


def b5(text):
    start = text.index("python3 - mcpb/manifest.json <<'PY'")
    end = text.index("\nPY\n", start) + len("\nPY\n")
    block = text[start:end]
    late = text[:start] + text[end:]
    anchor = 'chmod 755 "$work/linux-amd64/server/${binary}"'
    if late.count(anchor) != 1:
        return None
    return late.replace(anchor, block + "\n" + anchor)


def selftest(root):
    try:
        p = run(["bash", "scripts/catalog_selftest.sh"], root)
    except subprocess.TimeoutExpired:
        return None, "", "timeout after %ss" % TIMEOUT
    return p.returncode, p.stdout, p.stderr


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: selftest_mutants.py <kit_dir>")
    kit = os.path.abspath(sys.argv[1])
    tmp = tempfile.mkdtemp(prefix="catalog-m2c-mut-")
    root = os.path.join(tmp, "kit")
    p = run(["git", "clone", "-q", kit, root], tmp)
    if p.returncode != 0:
        sys.exit("FAIL: git clone: %s" % p.stderr.strip())
    if not os.path.isfile(os.path.join(root, "scripts/catalog_selftest.sh")):
        sys.exit("FAIL: scripts/catalog_selftest.sh is not committed")
    for rel, want in PINNED.items():
        with open(os.path.join(root, rel), "rb") as f:
            got = hashlib.sha256(f.read()).hexdigest()
        if got != want:
            sys.exit("FAIL: %s changed since base (sha256 %s); mutation targets must stay untouched" % (rel, got))

    rc, out, err = selftest(root)
    oks = set(re.findall(r"^ok (\S+)$", out, re.M))
    fails = re.findall(r"^FAIL (\S+?):? .*$|^FAIL (\S+)$", out, re.M)
    missing = [c for c in CASES if c not in oks]
    status = run(["git", "status", "--porcelain", "--ignored"], root).stdout
    if rc != 0 or missing or fails or status:
        print("FAIL: baseline self-test rc=%s missing ok-cases=%s FAIL-lines=%s tree-after=%r" % (rc, missing, fails, status))
        print("stdout tail:\n" + out[-2000:])
        print("stderr tail:\n" + err[-2000:])
        sys.exit(1)
    print("baseline: rc=0, %d cases ok, tree clean" % len(CASES))

    survivors = []
    for mid, group, rel, old, new, cases in MUTANTS:
        path = os.path.join(root, rel)
        with open(path, encoding="utf-8") as f:
            original = f.read()
        if mid == "B5":
            mutated = b5(original)
            if mutated is None:
                sys.exit("FAIL: %s anchor not found" % mid)
        else:
            if original.count(old) != 1:
                sys.exit("FAIL: %s anchor count %d in %s" % (mid, original.count(old), rel))
            mutated = original.replace(old, new, 1)
        mode = os.stat(path).st_mode
        try:
            with open(path, "w", encoding="utf-8") as f:
                f.write(mutated)
            os.chmod(path, mode)
            rc, out, err = selftest(root)
        finally:
            with open(path, "w", encoding="utf-8") as f:
                f.write(original)
            os.chmod(path, mode)
        failed = set()
        for m in re.finditer(r"^FAIL (\S+?)(?::|\s|$)", out, re.M):
            failed.add(m.group(1))
        hit = sorted(failed & set(cases))
        # Cases that do not exercise the mutated file must stay green: a self-test
        # that fails everything whenever a target changes kills nothing honestly.
        prefix = {"A": ("build-", "checksums-"),
                  "B": ("render-", "check-", "reject-", "commented-", "static-", "checksums-", "release-"),
                  "C": ("render-", "check-", "reject-", "commented-", "build-", "checksums-", "release-"),
                  "D": ("render-", "check-", "reject-", "commented-", "build-", "static-", "release-"),
                  "E": ("build-", "checksums-"),
                  "F": ("build-", "checksums-", "release-")}[group]
        collateral = sorted(c for c in failed if c.startswith(prefix))
        if collateral:
            survivors.append(mid)
            print("SURVIVED %s: unrelated cases failed too %s (self-test reacts to the file, not the behaviour)" % (mid, collateral))
        elif rc not in (None, 0) and hit:
            print("KILLED %s by %s" % (mid, ", ".join(hit)))
        else:
            survivors.append(mid)
            print("SURVIVED %s: rc=%s expected one of %s, FAIL cases seen %s" % (mid, rc, cases, sorted(failed)))
        status = run(["git", "status", "--porcelain", "--ignored"], root).stdout
        if status:
            sys.exit("FAIL: tree dirty after %s: %r" % (mid, status))
    if survivors:
        print("FAIL: %d survivor(s): %s" % (len(survivors), " ".join(survivors)))
        sys.exit(1)
    print("OK: all %d mutants killed by their own case" % len(MUTANTS))


if __name__ == "__main__":
    main()
