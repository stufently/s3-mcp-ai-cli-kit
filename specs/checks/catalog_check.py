#!/usr/bin/env python3
"""Acceptance probe for the provider catalog scaffolding (milestone catalog-m1).

Written by the coordinator, not by the executor. Stdlib only, run with python3 -I.

  catalog_check.py static <provider_dir>
  catalog_check.py mcpb   <provider_dir> <dist_dir> <version> <sums_file>
  catalog_check.py image  <provider_dir> <image_ref>

Exit 0 means every check passed. Every failure is printed as "FAIL: ...".
"""
import hashlib
import json
import os
import re
import select
import subprocess
import sys
import time
import zipfile

ATTEST = "actions/attest@1e69f48acb82d1966a394da916b4c1698aa569d6 # v4.2.2"
PUBLISHER_URL = "https://github.com/modelcontextprotocol/registry/releases/download/v1.8.1/mcp-publisher_linux_amd64.tar.gz"
PUBLISHER_SHA = "a06c9096dcb9727c13555b6be26c7effa707b01f06a4c561ba7a3635443cf2cc"
PLACEHOLDER = "introspection-placeholder-not-a-key"
ENV_SUFFIXES = [
    "ACCESS_KEY_ID", "SECRET_ACCESS_KEY", "POOL", "ENDPOINT", "ALLOW_INSECURE", "ALLOW",
    "DESTRUCTIVE_POLICY", "ALLOWED_BUCKETS", "ALLOWED_PREFIXES", "FILE_ROOT", "AUDIT_FILE",
]
ENV_MAP = {
    "ACCESS_KEY_ID": "access_key_id",
    "SECRET_ACCESS_KEY": "secret_access_key",
    "POOL": "pool",
    "ENDPOINT": "endpoint",
    "DESTRUCTIVE_POLICY": "destructive_policy",
    "ALLOWED_BUCKETS": "allowed_buckets",
    "ALLOWED_PREFIXES": "allowed_prefixes",
    "FILE_ROOT": "file_root",
}
ARGS = [
    "mcp",
    "--allow-write=${user_config.allow_write}",
    "--allow-delete=${user_config.allow_delete}",
    "--allow-admin=${user_config.allow_admin}",
]
TARGETS = [("linux", "amd64"), ("linux", "arm64"), ("darwin", "amd64"),
           ("darwin", "arm64"), ("windows", "amd64"), ("windows", "arm64")]
PLATFORM = {"linux": "linux", "darwin": "darwin", "windows": "win32"}

failures = []


def check(cond, msg):
    if not cond:
        failures.append(msg)
        print("FAIL: " + msg)
    return cond


def read_text(path):
    if not os.path.isfile(path):
        sys.exit("FAIL: missing file %s" % path)
    with open(path, encoding="utf-8") as f:
        return f.read()


def load_json(path):
    if not os.path.isfile(path):
        sys.exit("FAIL: missing file %s" % path)
    with open(path, encoding="utf-8") as f:
        raw = f.read()
    try:
        return json.loads(raw)
    except json.JSONDecodeError as e:
        sys.exit("FAIL: %s is not JSON (%s); start: %r" % (path, e, raw[:200]))


def facts(pdir):
    prof = read_text(os.path.join(pdir, "internal/provider/profile.yaml"))

    def field(name):
        m = re.search(r"^%s:\s*(\S.*?)\s*$" % name, prof, re.M)
        if not m:
            sys.exit("FAIL: profile.yaml has no %s" % name)
        return m.group(1)

    srv = load_json(os.path.join(pdir, "server.json"))
    pid = field("id")
    repo = "%s-s3-mcp-ai-cli" % pid
    return {
        "id": pid, "binary": field("binary"), "prefix": field("env_prefix"),
        "pool": field("default_pool"), "repo": repo,
        "name": "io.github.stufently/" + repo, "server": srv,
    }


def golden(pdir, name):
    with open(os.path.join(pdir, "testdata/tools", name), encoding="utf-8") as f:
        return sorted(line.strip() for line in f if line.strip())


def substitute(value, variables):
    if isinstance(value, str):
        for k, v in variables.items():
            value = value.replace("${" + k + "}", v)
        return value
    if isinstance(value, list):
        return [substitute(v, variables) for v in value]
    if isinstance(value, dict):
        return {k: substitute(v, variables) for k, v in value.items()}
    return value


def check_manifest_base(m, f, built_version=None):
    p, b = f["prefix"], f["binary"]
    check(m.get("manifest_version") == "0.3", "manifest_version must be 0.3")
    check(m.get("name") == f["repo"], "manifest name must be %s" % f["repo"])
    check(m.get("license") == "MIT", "manifest license must be MIT")
    if built_version is None:
        check("version" not in m, "base manifest must not carry version (build stamps it)")
    else:
        check(m.get("version") == built_version, "bundle version must be %s" % built_version)
    srv = m.get("server", {})
    check(srv.get("type") == "binary", "server.type must be binary")
    cfg = srv.get("mcp_config", {})
    check(cfg.get("args") == ARGS, "mcp_config.args must be %s" % ARGS)
    want_env = {p + k: "${user_config.%s}" % v for k, v in ENV_MAP.items()}
    check(cfg.get("env") == want_env, "mcp_config.env must be exactly %s" % want_env)
    uc = m.get("user_config", {})
    keys = set(ENV_MAP.values()) | {"allow_write", "allow_delete", "allow_admin"}
    check(set(uc) == keys, "user_config keys must be exactly %s, got %s" % (sorted(keys), sorted(uc)))
    for k, opt in uc.items():
        check(isinstance(opt.get("title"), str) and opt["title"].strip() != "", "user_config.%s needs title" % k)
        check(isinstance(opt.get("description"), str) and opt["description"].strip() != "",
              "user_config.%s needs description" % k)
    for k in ("access_key_id", "secret_access_key"):
        o = uc.get(k, {})
        check(o.get("type") == "string" and o.get("sensitive") is True and o.get("required") is True,
              "user_config.%s must be required sensitive string" % k)
        check("default" not in o, "user_config.%s must have no default" % k)
    defaults = {"pool": f["pool"], "endpoint": "", "destructive_policy": "confirm",
                "allowed_buckets": "", "allowed_prefixes": "", "file_root": ""}
    for k, d in defaults.items():
        o = uc.get(k, {})
        check(o.get("required") in (None, False), "user_config.%s must be optional" % k)
        check(o.get("default") == d, "user_config.%s default must be %r" % (k, d))
        check(o.get("type") == ("directory" if k == "file_root" else "string"),
              "user_config.%s has wrong type" % k)
        check(not o.get("sensitive"), "user_config.%s must not be sensitive" % k)
    for k in ("allow_write", "allow_delete", "allow_admin"):
        o = uc.get(k, {})
        check(o.get("type") == "boolean" and o.get("default") is False and not o.get("required"),
              "user_config.%s must be optional boolean default false" % k)
    # Simulate the desktop host: only required values given, defaults fill the rest.
    variables = {"__dirname": "/ext"}
    for k, o in uc.items():
        if "default" in o:
            variables["user_config." + k] = str(o["default"]).lower() if isinstance(o["default"], bool) else str(o["default"])
    variables["user_config.access_key_id"] = "AK"
    variables["user_config.secret_access_key"] = "SK"
    resolved = substitute(cfg, variables)
    check("${" not in json.dumps(resolved), "unresolved ${...} after substitution: %s" % resolved)
    check(resolved.get("args") == ["mcp", "--allow-write=false", "--allow-delete=false", "--allow-admin=false"],
          "resolved args wrong: %s" % resolved.get("args"))
    return m


def job_blocks(text):
    m = re.search(r"^jobs:\s*$", text, re.M)
    if not m:
        return {}
    body = text[m.end():]
    parts = re.split(r"^  ([A-Za-z0-9_-]+):\s*$", body, flags=re.M)
    return {parts[i]: parts[i + 1] for i in range(1, len(parts) - 1, 2)}


def check_release(text, f):
    repo = f["repo"]
    check(re.search(r'^on:\s*\n\s+push:\s*\n\s+tags:\s*\[\s*"v\*"\s*\]\s*$', text, re.M) is not None,
          'release.yml must trigger only on push tags ["v*"]')
    check("workflow_dispatch" not in text and "branches" not in text, "release.yml must not run on branches/dispatch")
    check(text.count(ATTEST) >= 3, "need >=3 uses of %s" % ATTEST)
    check(len(re.findall(r"actions/attest@", text)) == text.count(ATTEST), "every actions/attest must be the pinned v4.2.2 SHA")
    for needle in ["goreleaser/goreleaser:v2.18.3", "actions/checkout@v7.0.1", "docker/setup-buildx-action@v4.4.1",
                   "subject-checksums: dist/checksums.txt", "subject-path: dist-mcpb/*.mcpb",
                   "subject-name: ghcr.io/stufently/" + repo, "push-to-registry: true",
                   "bash scripts/build-mcpb.sh", "bash scripts/mcpb-checksums.sh dist-mcpb dist-mcpb/checksums.txt",
                   "gh release upload", PUBLISHER_URL, PUBLISHER_SHA, "sha256sum -c",
                   "mcp-publisher login github-oidc", "mcp-publisher publish",
                   "linux/amd64,linux/arm64", "--push", "ghcr.io/stufently/%s:" % repo]:
        check(needle in text, "release.yml must contain %r" % needle)
    secrets = set(re.findall(r"secrets\.([A-Za-z0-9_]+)", text))
    check(secrets <= {"GITHUB_TOKEN"}, "only secrets.GITHUB_TOKEN allowed, got %s" % sorted(secrets))
    jobs = job_blocks(text)
    check(set(jobs) == {"goreleaser", "image", "mcpb", "registry"},
          "jobs must be exactly goreleaser, image, mcpb, registry; got %s" % sorted(jobs))

    def needs(block):
        m = re.search(r"^    needs:\s*(.+)$", block, re.M)
        return set(re.findall(r"[A-Za-z0-9_-]+", m.group(1))) if m else set()

    def perms(block):
        m = re.search(r"^    permissions:\s*\n((?:      .+\n)+)", block, re.M)
        return dict(re.findall(r"^      ([a-z-]+):\s*(\S+)", m.group(1), re.M)) if m else {}

    g, i, mb, r = (jobs.get(k, "") for k in ("goreleaser", "image", "mcpb", "registry"))
    check(needs(i) == {"goreleaser"}, "image must need exactly goreleaser")
    check(needs(mb) == {"goreleaser"}, "mcpb must need exactly goreleaser")
    check({"image", "mcpb"} <= needs(r), "registry must need image and mcpb")
    check(re.search(r"^    if:.*contains\(github\.ref_name, '-'\)", r, re.M) is not None,
          "registry must skip prerelease tags (if: ... contains(github.ref_name, '-'))")
    check("server.json" in g and "GITHUB_REF_NAME" in g, "goreleaser job must compare the tag with server.json")
    want = {
        "goreleaser": {"contents": "write", "id-token": "write", "attestations": "write"},
        "image": {"packages": "write", "id-token": "write", "attestations": "write"},
        "mcpb": {"contents": "write", "id-token": "write", "attestations": "write"},
        "registry": {"id-token": "write"},
    }
    for name, need in want.items():
        got = perms(jobs.get(name, ""))
        for k, v in need.items():
            check(got.get(k) == v, "job %s must have permissions %s: %s (got %s)" % (name, k, v, got))
    rp = perms(r)
    check(rp.get("contents", "read") == "read" and "packages" not in rp, "registry job must not write contents/packages")
    check("mcp-publisher" not in g + i + mb, "mcp-publisher only in the registry job")


def check_dockerfile(text, f):
    last = text.rsplit("\nFROM ", 1)[-1]
    check(re.search(r'io\.modelcontextprotocol\.server\.name="%s"' % re.escape(f["name"]), last) is not None,
          "final stage must LABEL io.modelcontextprotocol.server.name=\"%s\"" % f["name"])
    check('org.opencontainers.image.source="https://github.com/stufently/%s"' % f["repo"] in last,
          "final stage must LABEL org.opencontainers.image.source")
    for k in ("ACCESS_KEY_ID", "SECRET_ACCESS_KEY"):
        check(re.search(r"%s%s=%s\b" % (re.escape(f["prefix"]), k, PLACEHOLDER), last) is not None,
              "final stage must ENV %s%s=%s" % (f["prefix"], k, PLACEHOLDER))
    check('ENTRYPOINT ["/%s"]' % f["binary"] in last and 'CMD ["mcp"]' in last, "ENTRYPOINT/CMD must stay")


def cmd_static(pdir):
    f = facts(pdir)
    s = f["server"]
    check(load_json(os.path.join(pdir, "glama.json")) ==
          {"$schema": "https://glama.ai/mcp/schemas/server.json", "maintainers": ["stufently"]}, "glama.json content")
    check(s.get("name") == f["name"], "server.json name must be %s" % f["name"])
    pk = s.get("packages", [])
    check(len(pk) == 1, "server.json must have one package")
    if pk:
        p0 = pk[0]
        check(p0.get("registryType") == "oci", "package registryType oci")
        check(p0.get("identifier") == "ghcr.io/stufently/%s:%s" % (f["repo"], s.get("version")),
              "OCI identifier must be ghcr.io/stufently/%s:<server.json version>" % f["repo"])
        check("version" not in p0, "OCI package must not have version (registry rejects it)")
        check(p0.get("transport") == {"type": "stdio"}, "transport stdio")
        names = [e.get("name") for e in p0.get("environmentVariables", [])]
        check(names == [f["prefix"] + x for x in ENV_SUFFIXES], "environmentVariables must stay as before")
    check_manifest_base(load_json(os.path.join(pdir, "mcpb/manifest.json")), f)
    check_release(read_text(os.path.join(pdir, ".github/workflows/release.yml")), f)
    check_dockerfile(read_text(os.path.join(pdir, "Dockerfile")), f)
    for ign in (".gitignore", ".dockerignore"):
        lines = read_text(os.path.join(pdir, ign)).split()
        check(any(x.strip("/") == "dist-mcpb" for x in lines), "%s must ignore dist-mcpb" % ign)
    for sc in ("scripts/build-mcpb.sh", "scripts/mcpb-checksums.sh"):
        path = os.path.join(pdir, sc)
        check(os.path.isfile(path) and os.access(path, os.X_OK), "%s must exist and be executable" % sc)


def cmd_mcpb(pdir, dist, version, sums):
    f = facts(pdir)
    b = f["binary"]
    base = load_json(os.path.join(pdir, "mcpb/manifest.json"))
    want = sorted("%s_%s_%s_%s.mcpb" % (b, version, o, a) for o, a in TARGETS)
    got = sorted(x for x in os.listdir(dist) if x.endswith(".mcpb"))
    check(got == want, "bundles must be exactly %s, got %s" % (want, got))
    all_tools = golden(pdir, "all.golden")
    sums_lines = {}
    if check(os.path.isfile(sums), "sums file %s missing" % sums):
        for line in open(sums, encoding="utf-8"):
            m = re.match(r"^([0-9a-f]{64})  (.+)$", line.rstrip("\n"))
            if m:
                sums_lines[m.group(2)] = m.group(1)
    for o, a in TARGETS:
        name = "%s_%s_%s_%s.mcpb" % (b, version, o, a)
        path = os.path.join(dist, name)
        if not os.path.isfile(path):
            continue
        data = open(path, "rb").read()
        check(sums_lines.get(name) == hashlib.sha256(data).hexdigest(), "%s: checksum line missing or wrong" % name)
        entry = "server/%s%s" % (b, ".exe" if o == "windows" else "")
        with zipfile.ZipFile(path) as z:
            names = sorted(n for n in z.namelist() if not n.endswith("/"))
            check(names == sorted(["manifest.json", entry]), "%s: contents must be manifest.json + %s, got %s" % (name, entry, names))
            if "manifest.json" not in names or entry not in names:
                continue
            m = json.loads(z.read("manifest.json"))
            binary = z.read(entry)
        magic = {"linux": b"\x7fELF", "windows": b"MZ", "darwin": b"\xcf\xfa\xed\xfe"}[o]
        check(binary[:len(magic)] == magic, "%s: %s is not a %s binary" % (name, entry, o))
        check(m.get("compatibility", {}).get("platforms") == [PLATFORM[o]], "%s: platforms must be [%s]" % (name, PLATFORM[o]))
        check(m.get("server", {}).get("entry_point") == entry, "%s: entry_point" % name)
        check(m.get("server", {}).get("mcp_config", {}).get("command") == "${__dirname}/" + entry, "%s: command" % name)
        check(sorted(t.get("name") for t in m.get("tools", [])) == all_tools, "%s: tools must equal all.golden" % name)
        check(all(isinstance(t.get("description"), str) and t["description"] for t in m.get("tools", [])),
              "%s: every tool needs a description" % name)
        check(m.get("user_config") == base.get("user_config"), "%s: user_config differs from mcpb/manifest.json" % name)
        check_manifest_base(m, f, built_version=version)


def mcp_probe(image):
    cmd = ["docker", "run", "--rm", "-i", "--network", "none", image]
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    buf = b""

    def send(obj):
        proc.stdin.write((json.dumps(obj) + "\n").encode())
        proc.stdin.flush()

    def wait_for(rid, timeout):
        nonlocal buf
        deadline = time.time() + timeout
        while time.time() < deadline:
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                try:
                    msg = json.loads(line)
                except ValueError:
                    continue
                if isinstance(msg, dict) and msg.get("id") == rid:
                    return msg
            ready, _, _ = select.select([proc.stdout], [], [], 1.0)
            if ready:
                chunk = os.read(proc.stdout.fileno(), 65536)
                if not chunk:
                    err = proc.stderr.read().decode("utf-8", "replace")[-1000:]
                    sys.exit("FAIL: server exited before answering id %s; stderr: %s" % (rid, err))
                buf += chunk
        sys.exit("FAIL: timeout waiting for id %s" % rid)

    try:
        send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
            "protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "catalog-check", "version": "1"}}})
        init = wait_for(1, 60)
        send({"jsonrpc": "2.0", "method": "notifications/initialized"})
        send({"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}})
        tools = wait_for(2, 30)
    finally:
        try:
            proc.stdin.close()
        except OSError:
            pass
        try:
            proc.wait(timeout=15)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
    return init, tools


def cmd_image(pdir, image):
    f = facts(pdir)
    out = subprocess.run(["docker", "image", "inspect", image, "--format", "{{json .Config.Labels}}"],
                         capture_output=True, text=True)
    if not check(out.returncode == 0, "docker image inspect failed: %s" % out.stderr.strip()):
        return
    labels = json.loads(out.stdout or "null") or {}
    check(labels.get("io.modelcontextprotocol.server.name") == f["name"],
          "image label io.modelcontextprotocol.server.name must be %s, got %r" % (f["name"], labels.get("io.modelcontextprotocol.server.name")))
    init, tools = mcp_probe(image)
    check("error" not in init and init.get("result", {}).get("serverInfo", {}).get("name") == f["binary"],
          "initialize must succeed with serverInfo.name %s: %s" % (f["binary"], json.dumps(init)[:300]))
    names = sorted(t.get("name") for t in tools.get("result", {}).get("tools", []))
    check(names == golden(pdir, "read.golden"), "tools/list without keys must equal read.golden, got %s" % names)


def main(argv):
    if len(argv) < 3:
        sys.exit(__doc__)
    mode = argv[1]
    if mode == "static" and len(argv) == 3:
        cmd_static(argv[2])
    elif mode == "mcpb" and len(argv) == 6:
        cmd_mcpb(argv[2], argv[3], argv[4], argv[5])
    elif mode == "image" and len(argv) == 4:
        cmd_image(argv[2], argv[3])
    else:
        sys.exit(__doc__)
    if failures:
        print("%d check(s) failed" % len(failures))
        return 1
    print("OK: %s" % mode)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
