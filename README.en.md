# S3 MCP & AI CLI kit

Shared Go toolkit for S3 MCP servers, streaming CLIs and installable agent skills. Seven provider projects connect Claude Code, Cursor and Codex to Selectel, Yandex Cloud, VK Cloud, Cloud.ru Evolution, Timeweb Cloud, MWS Cloud Platform and Beget object storage. Read-only defaults, scoped access and signed human approvals are shared; each cloud has its own YAML capability profile.

[Русское руководство](README.md) · [Provider directory](https://stufently.github.io/s3-mcp-ai-cli-kit/en/)

## Providers

| Provider | Repository | Use case |
|---|---|---|
| Selectel | [selectel-s3-mcp-ai-cli](https://github.com/stufently/selectel-s3-mcp-ai-cli) | Pool selection and backup recovery |
| Yandex Cloud | [yandex-s3-mcp-ai-cli](https://github.com/stufently/yandex-s3-mcp-ai-cli) | Object inventory and backup version inspection |
| VK Cloud | [vkcloud-s3-mcp-ai-cli](https://github.com/stufently/vkcloud-s3-mcp-ai-cli) | Hotbox/Icebox inspection and regional access |
| Cloud.ru | [cloudru-s3-mcp-ai-cli](https://github.com/stufently/cloudru-s3-mcp-ai-cli) | Evolution Object Storage access diagnostics |
| Timeweb Cloud | [timeweb-s3-mcp-ai-cli](https://github.com/stufently/timeweb-s3-mcp-ai-cli) | Archive recovery and bounded prefix usage |
| MWS | [mws-s3-mcp-ai-cli](https://github.com/stufently/mws-s3-mcp-ai-cli) | HMAC access checks and short-lived archive URLs |
| Beget | [beget-s3-mcp-ai-cli](https://github.com/stufently/beget-s3-mcp-ai-cli) | Browse and restore files from an existing bucket |
| Shared Go kit | [s3-mcp-ai-cli-kit](https://github.com/stufently/s3-mcp-ai-cli-kit) | Shared MCP, CLI, safety and CI |

Each provider has bilingual guides, official-documentation research, a capability profile and pending live checks. A directory entry does not mean all clouds expose identical or live-verified APIs.

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

## Social preview

[Artwork and GitHub upload instructions](docs/social-preview.md). The family site has its own Open Graph image; repository previews require a separate GitHub Settings upload.
