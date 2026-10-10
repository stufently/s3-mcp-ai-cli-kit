# S3 MCP & AI CLI kit

Shared Go module for provider-specific S3 MCP servers, streaming CLIs and installable agent skills. MIT licensed. Provider repositories embed a YAML profile and call `cli.New(profile, version, commit)`.

## Packages

- `provider`: YAML profile types and decoder.
- `cli`, `install`, `skills`: streaming CLI, atomic MCP installation and profile-rendered skills.
- `mcpserver`, `s3core`, `analytics`: capability-filtered MCP registry, S3 operations and bounded scans.
- `safety`: independent permission levels, signed one-use confirmations, scope, confined local files, redaction and audit.
- `conformance`: reusable Docker gateway checks for a provider profile and its thin binary.

## Usage

```go
profile, err := provider.Load(embeddedYAML)
if err != nil { return err }
return cli.New(profile, version, commit).Execute()
```

Pin the module and reusable `.github/workflows/provider-ci.yml` to the same release. Shared checks live in `scripts/`; provider wrappers download the pinned module and invoke those checks. All local compilation and verification run in Docker as the caller uid. Mutation runs use a private copy, protecting the module cache and checked-out source.

## Verification

`bash scripts/verify.sh` runs build, vet, race tests, golangci-lint, versitygw conformance, stdio smoke, mutation gates and actionlint. The embedded Selectel profile under `internal/testprofile` is an accepted test fixture, not a live-service claim. Provider checks additionally validate bilingual docs, generated compatibility, Registry schema and GoReleaser snapshots. See [TASKS.md](TASKS.md) for status and [CHANGELOG.md](CHANGELOG.md) for user changes.

## Safety

Read-only defaults; capability-disabled tools are absent. Destructive actions require the configured human approval policy. Scope and local file roots apply before S3 I/O. Credentials and signatures are redacted from diagnostics and audit. Tests cover the full permission matrix, HTTP statuses and rejected confirmation reasons. Emulation never proves a cloud's conditional headers or limits; live checks require the owner's test account.

## License

[MIT](LICENSE).
