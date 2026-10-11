# S3 MCP & AI CLI kit

Общий Go-модуль для MCP-серверов, CLI и skills российских S3-хранилищ: Selectel (Селектел), Яндекс Облако, VK Cloud, Cloud.ru Evolution, Timeweb Cloud, MWS Cloud Platform и Beget (Бегет). Провайдеры используют один код MCP, передачи файлов и защит, а различия задают YAML-профилем.

[English guide](README.en.md) · [Каталог S3 MCP-серверов](https://stufently.github.io/s3-mcp-ai-cli-kit/)

## English

A shared Go toolkit for S3 MCP servers, streaming CLIs and agent skills. Seven provider projects connect Claude Code, Cursor and Codex to Russian object storage services with read-only defaults, scoped access and signed human approvals.

## Провайдеры

| Провайдер | Репозиторий | Сценарий |
|---|---|---|
| Selectel | [selectel-s3-mcp-ai-cli](https://github.com/stufently/selectel-s3-mcp-ai-cli) | Выбор пула и восстановление резервных копий |
| Yandex Cloud | [yandex-s3-mcp-ai-cli](https://github.com/stufently/yandex-s3-mcp-ai-cli) | Инвентаризация объектов и проверка версий бэкапов |
| VK Cloud | [vkcloud-s3-mcp-ai-cli](https://github.com/stufently/vkcloud-s3-mcp-ai-cli) | Проверка Hotbox/Icebox и доступ к нужному региону |
| Cloud.ru | [cloudru-s3-mcp-ai-cli](https://github.com/stufently/cloudru-s3-mcp-ai-cli) | Диагностика доступа к Evolution Object Storage |
| Timeweb Cloud | [timeweb-s3-mcp-ai-cli](https://github.com/stufently/timeweb-s3-mcp-ai-cli) | Восстановление архивов и учёт объёма префикса |
| MWS | [mws-s3-mcp-ai-cli](https://github.com/stufently/mws-s3-mcp-ai-cli) | Проверка HMAC-доступа и короткие ссылки на архивы |
| Beget | [beget-s3-mcp-ai-cli](https://github.com/stufently/beget-s3-mcp-ai-cli) | Просмотр и восстановление файлов из готового бакета |
| Shared Go kit | [s3-mcp-ai-cli-kit](https://github.com/stufently/s3-mcp-ai-cli-kit) | Общие MCP, CLI, защиты и CI |

Каждый проект содержит свой README RU/EN, профиль возможностей, ресерч официальной документации и статус живой проверки. Каталог не означает, что все возможности одинаковы или уже проверены на реальном облаке.

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
