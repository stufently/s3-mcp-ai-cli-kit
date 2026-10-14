# Каталожная обвязка S3 MCP: шаблон в kit + пилот на Selectel (веха 1)

Дата: 14.10.2026. Репозитории: `s3-mcp-ai-cli-kit` (шаблон) и `selectel-s3-mcp-ai-cli` (пилот).
BASE kit: `a86354f1f6b25f113d9d23774d7ee368cba8166e` — `Record accepted directory indexing requests`.
BASE selectel: `638376907b7cfdf6b7aee5f20db7d2be4f81a8d1` — `Record fresh Docker installation checks`.
Исполнитель: `auto` (выбор лаунчера). Мутации/зонды по этой вехе потом гоняет
противоположный исполнитель. Решение владельца 14.10.2026: обвязку делать сейчас,
теги и релизы — только после живой проверки в облаках.

## Где работать

Два одноразовых клона, оба созданы `make_clone.sh`, push в обоих закрыт:

- kit: `/home/deploy/exec-clones/s3kit-catalog-m1` — основной клон вехи (здесь спека и `report.json`);
- selectel: `/home/deploy/exec-clones/s3sel-catalog-m1` — клон пилота.

В КАЖДОМ клоне создать ветку `catalog-m1` от BASE и коммитить туда. Живые деревья
`~/github/*` не трогать (читать можно). **Push в origin запрещён в обоих клонах,
теги не создавать** — работу заберёт постановщик через `git fetch` из клонов.

Что положил постановщик (untracked в kit-клоне, закоммитить вместе с работой, НЕ редактировать):

| Файл | sha256 |
|---|---|
| `specs/catalog-m1.md` | (эта спека) |
| `specs/checks/catalog_check.py` | `147e0e9e0f8dbced0f1d23bdf36c1cdff4c689144ae6231086d7d010f601fd5b` |

`catalog_check.py` — пробник приёмки (stdlib, `python3 -I`). Читать его можно и
нужно: это самое точное описание контракта. Если его требование противоречит
спеке — стоп по контракту на невыполнимое, пробник не править.

Docker на хосте есть, образы `golang:1.27.2`, `goreleaser/goreleaser:v2.18.3`,
`rhysd/actionlint:1.7.12`, `koalaman/shellcheck:v0.11.0`, `node:24.21.0-slim` уже
скачаны. Все `docker run` — под `-u "$(id -u):$(id -g)"` (у deploy это 1002:1002).
На хост ничего не ставить.

## Задача и почему

Семь провайдерских S3 MCP (`stufently/{beget,mws,timeweb,cloudru,vkcloud,yandex,selectel}-s3-mcp-ai-cli`)
надо довести до каталожного уровня эталона `stufently/zabbix-ai-cli-mcp`: `glama.json`,
Desktop Extension `.mcpb` под 6 платформ в релизе и в `checksums.txt`, build provenance
(`actions/attest`) для архивов, `.mcpb` и образа ghcr, публикация в официальный MCP Registry
по GitHub OIDC, LABEL `io.modelcontextprotocol.server.name` в образе, образ по умолчанию
отвечает на `initialize`/`tools/list` без настоящих ключей (интроспекция Glama).

Все семь репо одинаковы с точностью до имени провайдера (проверено diff'ом release.yml,
Dockerfile и списков env в server.json), поэтому обвязка делается ОДИН раз шаблоном в kit
и раскатывается рендером. Эта веха: шаблон + рендерер в kit и пилот — результат рендера,
закоммиченный в selectel-клон. Раскатка на остальные 6 — следующая веха.

Почему рендер, а не reusable workflow из kit: провайдеры тянут kit тегом
(`go.mod` — `v0.1.0`, `ci.yml` — `provider-ci.yml@v0.1.0`), новые теги запрещены; у
reusable workflow подпись attestation и OIDC-идентичность принадлежат workflow kit, а не
репо провайдера. Отрендеренный самодостаточный `release.yml` в каждом репо снимает обе
проблемы, а `provider_scaffold.sh --check` ловит дрейф копий.

Почему `mcp-publisher`, а не goreleaser-блок `mcp:`: `server.json` уже лежит в репо и
остаётся единственным источником правды; goreleaser здесь запускается в Docker (OIDC-env
внутрь не проброшен), а образ собирается buildx ПОСЛЕ goreleaser — блок `mcp:` пытался бы
публиковать раньше, чем образ появится в ghcr.

Что СЛОМАНО сейчас и чинится в этой вехе (в пилоте и шаблоне):
1. `server.json` у OCI-пакета держит отдельное поле `"version"`, а identifier без тега —
   Registry такое отвергает при publish.
2. Образ без ключей не стартует: `selectel-s3 mcp` → `credentials not configured`, rc=1.
3. В образе нет LABEL `io.modelcontextprotocol.server.name` — Registry не примет OCI-пакет.

## Что проверено вживую, а что предположение

- `internal/provider/profile.yaml` селектела: `id: selectel`, `display_name: Selectel`,
  `env_prefix: SELECTEL_S3_`, `binary: selectel-s3`, `default_pool: ru-1`. У всех семи
  провайдеров те же ключи; `display_name` и `description` в server.json — ASCII.
- `cmd/<binary>/main.go` у провайдера: `var version`, `var commit` (ldflags в
  `.goreleaser.yaml`: `-X main.version={{.Version}} -X main.commit={{.ShortCommit}}`).
- kit `config/config.go`: значение env берётся через `os.LookupEnv`; ПУСТАЯ строка
  равносильна «не задано» (пул по умолчанию, policy `confirm`, пустой скоуп). `ALLOW` —
  список `write,delete,admin`. Флаги `mcp --allow-write/--allow-delete/--allow-admin` (cobra
  bool) при явном значении перекрывают `ALLOW`.
- kit `cli/cli.go` `addMCP`: без ACCESS_KEY_ID/SECRET_ACCESS_KEY — `credentials not configured`.
  С любыми непустыми значениями и `--network none` сервер отвечает: `initialize` →
  `serverInfo.name = selectel-s3`; `tools/list` = 13 инструментов = `testdata/tools/read.golden`;
  с `SELECTEL_S3_ALLOW=write,delete,admin` — 31 = `testdata/tools/all.golden`
  (сравнивать отсортированными в C-порядке; `sort` с локалью даёт другой порядок).
- Registry v1.8.1, `internal/validators/registries/oci.go`: OCI-пакет с полем `version`
  отвергается (`OCI packages must not have 'version' field - include version in 'identifier'`);
  образ проверяется анонимно (должен быть публичным) на LABEL = `name` из server.json.
  `/v0/validate` эту проверку НЕ делает (на текущем server.json отвечает valid).
- `mcp-publisher` v1.8.1: `mcp-publisher_linux_amd64.tar.gz`, sha256
  `a06c9096dcb9727c13555b6be26c7effa707b01f06a4c561ba7a3635443cf2cc` (совпадает с
  `registry_1.8.1_checksums.txt`); команды `login github-oidc`, `publish [server.json]`.
- Последние версии (реестр, 14.10.2026): goreleaser v2.18.3, actionlint 1.7.12,
  actions/checkout v7.0.1, docker/setup-buildx-action v4.4.1, actions/attest v4.2.2
  (пин `1e69f48acb82d1966a394da916b4c1698aa569d6`), `@anthropic-ai/mcpb` 2.1.2,
  Node LTS 24.21.0, Go 1.27.2, shellcheck v0.11.0.
- mcpb 2.1.2 (`src/shared/config.ts`): `${user_config.X}` подставляется и ВНУТРИ строки
  (`"--allow-write=${user_config.allow_write}"` работает); значение без default и без ввода
  пользователя НЕ подставляется — литерал `${user_config.X}` уйдёт в env как есть. Поэтому
  у каждого необязательного поля обязателен `default` (для строк — `""`).
- `npx -y @anthropic-ai/mcpb@2.1.2 pack <dir> <out>` в `node:24.21.0-slim` упаковывает
  каталог `manifest.json + server/<binary>` ровно в эти два файла; манифест с
  `"type": "directory", "default": ""` проходит pack.
- Эталон zabbix: `scripts/build-mcpb.sh` (6 целей, tools/list с живого бинаря, per-platform
  manifest, pack), `scripts/mcpb-checksums.sh` (дописывает строки `.mcpb` в checksums.txt,
  сохраняя строки goreleaser), `release.yml` (attest архивов по `subject-checksums`, образа с
  `push-to-registry`, `.mcpb` по `subject-path`). Брать как образец логики, лицензия своя.
- Положительный зонд постановщика (копия selectel с ручной правильной обвязкой):
  `catalog_check.py static` → OK, `image` → OK, actionlint → 0. Отрицательный: на чистом
  селектеле `static`/`image` падают по задуманной причине. Режим `mcpb` против настоящей
  сборки НЕ прогонялся (предположение: формат пробника верен; layout zip подтверждён pack'ом).
- ПРЕДПОЛОЖЕНИЯ (не проверить без тега): пакет ghcr, созданный из Actions, окажется
  публичным; OIDC-логин Registry пройдёт для `io.github.stufently/*`. Это проверит владелец
  на первом теге; в этой вехе не трогать.

## Что сделать

### A. kit-клон

1. `templates/provider/` — шаблоны с плейсхолдерами вида `@@NAME@@` (ровно этот набор):
   `@@ID@@`, `@@BINARY@@`, `@@ENV_PREFIX@@`, `@@DEFAULT_POOL@@`, `@@DISPLAY_NAME@@`,
   `@@REPO@@` (= `<id>-s3-mcp-ai-cli`), `@@SERVER_NAME@@` (= `io.github.stufently/@@REPO@@`),
   `@@DESCRIPTION@@` (= `description` из server.json). Файлы:
   - `glama.json` — ровно `{"$schema": "https://glama.ai/mcp/schemas/server.json", "maintainers": ["stufently"]}`;
   - `Dockerfile` — текущий Dockerfile провайдера (у всех семи одинаков с точностью до имени
     бинаря → `@@BINARY@@`) + в финальной стадии
     `LABEL io.modelcontextprotocol.server.name="@@SERVER_NAME@@"` и
     `org.opencontainers.image.source="https://github.com/stufently/@@REPO@@"`, плюс
     `ENV @@ENV_PREFIX@@ACCESS_KEY_ID=introspection-placeholder-not-a-key` и то же для
     `SECRET_ACCESS_KEY`, с комментарием: заглушка только для интроспекции, настоящие ключи
     передаются `-e` и перекрывают её. ENTRYPOINT/CMD (`mcp`) не менять;
   - `release.yml` (рендерится в `.github/workflows/release.yml`) — четыре job'а ровно с
     именами `goreleaser`, `image`, `mcpb`, `registry`; триггер только `push: tags: ["v*"]`;
     верхнеуровневые `permissions: contents: read`, права — по job'ам:
     - `goreleaser` (contents/id-token/attestations/artifact-metadata: write): checkout с
       `fetch-depth: 0`; шаг сверки тега: `${GITHUB_REF_NAME#v}` == `.version` server.json И
       `.packages[0].identifier` == `ghcr.io/stufently/@@REPO@@:<версия>`, иначе exit 1;
       goreleaser в Docker как сейчас (`goreleaser/goreleaser:v2.18.3 release --clean`);
       attest `subject-checksums: dist/checksums.txt`;
     - `image` (needs goreleaser; contents: read, packages/id-token/attestations/artifact-metadata: write):
       buildx `linux/amd64,linux/arm64`, тег `ghcr.io/stufently/@@REPO@@:${TAG#v}`, `--push`,
       `--metadata-file`, digest из `containerimage.digest`; attest `subject-name:
       ghcr.io/stufently/@@REPO@@`, `subject-digest`, `push-to-registry: true`;
     - `mcpb` (needs goreleaser; contents/id-token/attestations/artifact-metadata: write):
       `VERSION="${GITHUB_REF_NAME#v}" bash scripts/build-mcpb.sh`; `gh release download
       … --pattern checksums.txt --dir dist-mcpb`; `bash scripts/mcpb-checksums.sh dist-mcpb
       dist-mcpb/checksums.txt`; attest `subject-path: dist-mcpb/*.mcpb`; `gh release upload
       … dist-mcpb/*.mcpb dist-mcpb/checksums.txt --clobber`;
     - `registry` (needs `[image, mcpb]`; `if: ${{ !contains(github.ref_name, '-') }}` —
       пре-релизы в Registry не публикуются; contents: read, id-token: write): скачать
       mcp-publisher v1.8.1 linux_amd64 по полному URL релиза, `sha256sum -c` по пину выше,
       `mcp-publisher login github-oidc`, `mcp-publisher publish server.json`.
     Все `actions/attest` — ровно `actions/attest@1e69f48acb82d1966a394da916b4c1698aa569d6 # v4.2.2`.
     Секреты — только `GITHUB_TOKEN`. Образец формы — `release.yml` эталона zabbix.
   - `mcpb/manifest.json` — `manifest_version: "0.3"`, `name: @@REPO@@`, `display_name`,
     `description`, `author: {name: stufently}`, `repository`, `homepage`, `support`,
     `license: "MIT"`, `keywords`, `server.type: binary`, `entry_point: server/@@BINARY@@`,
     `mcp_config.command: ${__dirname}/server/@@BINARY@@`, `args` ровно
     `["mcp", "--allow-write=${user_config.allow_write}", "--allow-delete=${user_config.allow_delete}", "--allow-admin=${user_config.allow_admin}"]`,
     `env` ровно 8 ключей `@@ENV_PREFIX@@{ACCESS_KEY_ID,SECRET_ACCESS_KEY,POOL,ENDPOINT,DESTRUCTIVE_POLICY,ALLOWED_BUCKETS,ALLOWED_PREFIXES,FILE_ROOT}`
     → `${user_config.<snake_case>}`; `user_config` ровно 11 полей: `access_key_id`,
     `secret_access_key` (string, sensitive, required, без default); `pool` (string, default
     `@@DEFAULT_POOL@@`); `endpoint`, `allowed_buckets`, `allowed_prefixes` (string, default `""`);
     `destructive_policy` (string, default `"confirm"`); `file_root` (directory, default `""`);
     `allow_write`, `allow_delete`, `allow_admin` (boolean, default false). У каждого — непустые
     `title` и `description` (по-английски, по делу: что значит пустое значение, что off = только
     чтение). `version` и `tools` в шаблоне НЕТ — их ставит сборка. `ALLOW_INSECURE` и
     `AUDIT_FILE` в Desktop не выводить.
2. `scripts/build-mcpb.sh` — обобщённая версия zabbix'овской, запускается из корня
   провайдера, ничего не ставит на хост (Go и mcpb — в Docker, кэш Go `$HOME/.cache/sel-s3-go`):
   `VERSION` обязателен (без него — сообщение со словом `VERSION` в stderr, rc≠0) и проходит
   ту же проверку безопасного токена; `binary`, `env_prefix`
   читает из `internal/provider/profile.yaml`; собирает 6 целей
   (linux/darwin/windows × amd64/arm64) из `./cmd/<binary>` c `CGO_ENABLED=0 -trimpath`,
   ldflags `-s -w -X main.version=$VERSION -X main.commit=${COMMIT:-mcpb}`; снимает
   `tools/list` с linux-amd64 бинаря в контейнере `--network none` с фиктивными ключами,
   `ENDPOINT=http://127.0.0.1:1`, `ALLOW_INSECURE=1`, `ALLOW=write,delete,admin` и требует,
   чтобы отсортированные имена совпали с `testdata/tools/all.golden`; ДО сборки проверяет, что у каждого
   необязательного поля `mcpb/manifest.json` есть default (иначе rc≠0 и имя поля в stderr,
   бандлы не создаются); пишет per-platform manifest
   (`version`, `tools` с описаниями из tools/list, `compatibility.platforms` =
   `linux|darwin|win32`, `entry_point`/`command` с `.exe` для windows); пакует
   `npx -y @anthropic-ai/mcpb@2.1.2 pack` в `node:24.21.0-slim` в
   `dist-mcpb/<binary>_<VERSION>_<os>_<arch>.mcpb` (то же имя, что у архивов goreleaser);
   при числе бандлов ≠ 6 — exit 1. Внутри бандла — только `manifest.json` и `server/<binary>[.exe]`.
3. `scripts/mcpb-checksums.sh` — перенести zabbix'овский без изменения поведения.
4. `scripts/provider_scaffold.sh [--check]` — запуск из корня провайдера
   (`bash <kit>/scripts/provider_scaffold.sh`); корень kit — по пути самого скрипта.
   Берёт значения из `profile.yaml` и `server.json`; любое значение вне
   `[A-Za-z0-9 ._,:/()-]` — отказ rc≠0. Без флага: рендерит 4 шаблона (`glama.json`,
   `Dockerfile`, `.github/workflows/release.yml`, `mcpb/manifest.json`), копирует
   байт-в-байт `scripts/build-mcpb.sh` и `scripts/mcpb-checksums.sh` (режим 0755),
   нормализует `server.json` через `jq` (`packages[0].identifier =
   "ghcr.io/stufently/<repo>:" + .version`, `del(.packages[0].version)`, прочее как есть),
   дописывает `/dist-mcpb/` в `.gitignore` и `dist-mcpb` в `.dockerignore`, если их там нет.
   Повторный запуск ничего не меняет. `--check`: ничего не пишет, rc=0 только если каждый
   из этих файлов совпадает с тем, что дал бы рендер; иначе печатает расходящиеся пути, rc=1.
   jq — с хоста (на GitHub runner он есть).
5. `CHANGELOG.md` kit — одна запись про шаблон.

### B. selectel-клон (пилот)

Выполнить в `/home/deploy/exec-clones/s3sel-catalog-m1`:
`bash /home/deploy/exec-clones/s3kit-catalog-m1/scripts/provider_scaffold.sh`, руками ничего
из отрендеренного не править (нужна правка — правь шаблон в kit и рендери заново), добавить
одну запись в `CHANGELOG.md` (раздел Unreleased), закоммитить в ветку `catalog-m1`.

## Не трогать

- Никаких тегов, релизов, `git push`, `gh release`, публикаций в ghcr/Registry, `docker push`.
- Бизнес-логику серверов: весь Go-код kit и провайдера, `go.mod/go.sum`, `.goreleaser.yaml`,
  `ci.yml`, `provider-ci.yml`, `profile.yaml`, `testdata/`, README, skills, docs-сайт kit.
- Живые деревья `~/github/*`; файлы пробника `specs/checks/catalog_check.py` и эту спеку
  (только закоммитить).
- Ожидаемые изменения, РОВНО:
  kit — `templates/provider/**`, `scripts/build-mcpb.sh`, `scripts/mcpb-checksums.sh`,
  `scripts/provider_scaffold.sh`, `CHANGELOG.md`, `specs/catalog-m1.md`,
  `specs/checks/catalog_check.py`;
  selectel — `glama.json`, `Dockerfile`, `server.json`, `.github/workflows/release.yml`,
  `mcpb/manifest.json`, `scripts/build-mcpb.sh`, `scripts/mcpb-checksums.sh`, `.gitignore`,
  `.dockerignore`, `CHANGELOG.md`.

## Разрешения

Чтение всех репо (`~/github/zabbix-ai-cli-mcp` — эталон), правка перечисленных файлов,
Docker под своим uid, сеть для Go-модулей и npm, локальные коммиты в обоих клонах
(≤50 символов, imperative, без подписей и Co-Authored-By).

## Авторевью

В этой вехе исполнитель ревьюеров НЕ зовёт. Независимые ревью диапазонов BASE..HEAD обоих
клонов, мутации и раскатку проводит постановщик/владелец после `report.json`.

## Контракт на невыполнимое

Требование пробника противоречит спеке; нужен файл вне списка; без правки Go-кода сервер
не проходит критерий; сеть/Docker не дают выполнить команду — остановись, запиши причину в
`report-blocked.md` в корне kit-клона и в отчёт (`blocked`, `"rc": null`, дословная ошибка).
Обходить несовместимость (менять пробник, подменять окружение, глушить коды возврата) запрещено.

## Стыки с соседними вехами

Следующая веха (раскатка) прогонит `provider_scaffold.sh` в остальных шести репо и критерии
этой вехи против каждого. Эта веха обещает: рендерер не зависит от имени провайдера
(проверяется рендером на копии beget), а пилотные файлы селектела — чистый вывод рендера.

## Контракт отчёта

`report.json` в корне kit-клона, untracked:
`{"criteria": [{"id": "AC-001", "status": "pass|fail|blocked", "command": "<команда из спеки>", "rc": 0, "note": "…"}]}` —
ровно 11 записей, по одной на критерий; у `blocked` `"rc": null` и дословная ошибка.

## Критерии приёмки

Команды запускаются из корня kit-клона.

**AC-001 — В kit изменены только разрешённые пути, спека и пробник закоммичены, дерево чистое.**
`bash -c 'set -e; B=a86354f1f6b25f113d9d23774d7ee368cba8166e; test "$(git branch --show-current)" = catalog-m1; git diff --check $B HEAD; git diff --quiet $B HEAD -- . ":(exclude)templates/provider" ":(exclude)scripts/build-mcpb.sh" ":(exclude)scripts/mcpb-checksums.sh" ":(exclude)scripts/provider_scaffold.sh" ":(exclude)CHANGELOG.md" ":(exclude)specs/catalog-m1.md" ":(exclude)specs/checks/catalog_check.py"; git ls-files --error-unmatch specs/catalog-m1.md specs/checks/catalog_check.py templates/provider/release.yml templates/provider/Dockerfile templates/provider/glama.json templates/provider/mcpb/manifest.json scripts/provider_scaffold.sh >/dev/null; test -z "$(git status --porcelain -- . ":(exclude)report.json" ":(exclude)report-blocked.md")"'`

**AC-002 — В selectel изменены только разрешённые пути, всё закоммичено в catalog-m1, дерево чистое.**
`bash -c 'set -e; cd /home/deploy/exec-clones/s3sel-catalog-m1; B=638376907b7cfdf6b7aee5f20db7d2be4f81a8d1; test "$(git branch --show-current)" = catalog-m1; git diff --check $B HEAD; git diff --quiet $B HEAD -- . ":(exclude)glama.json" ":(exclude)Dockerfile" ":(exclude)server.json" ":(exclude).github/workflows/release.yml" ":(exclude)mcpb/manifest.json" ":(exclude)scripts/build-mcpb.sh" ":(exclude)scripts/mcpb-checksums.sh" ":(exclude).gitignore" ":(exclude).dockerignore" ":(exclude)CHANGELOG.md"; git ls-files --error-unmatch glama.json mcpb/manifest.json scripts/build-mcpb.sh scripts/mcpb-checksums.sh >/dev/null; test -z "$(git status --porcelain -- . ":(exclude)report.json" ":(exclude)report-blocked.md")"'`

**AC-003 — Shellcheck чист на трёх новых скриптах kit.**
`bash -c 'docker run --rm -u "$(id -u):$(id -g)" -v "$PWD:/mnt:ro" -w /mnt koalaman/shellcheck:v0.11.0 scripts/build-mcpb.sh scripts/mcpb-checksums.sh scripts/provider_scaffold.sh'`

**AC-004 — Пилот совпадает с рендером, а check ловит дрейф (правка release.yml и возврат version в server.json).**
`bash -c 'set -e; K=$PWD; cd /home/deploy/exec-clones/s3sel-catalog-m1; bash $K/scripts/provider_scaffold.sh --check; d=$(mktemp -d); git clone -q /home/deploy/exec-clones/s3sel-catalog-m1 $d/a; git -C $d/a checkout -q catalog-m1; echo "# drift" >> $d/a/.github/workflows/release.yml; if (cd $d/a && bash $K/scripts/provider_scaffold.sh --check); then echo "drift in release.yml not caught"; exit 1; fi; git clone -q /home/deploy/exec-clones/s3sel-catalog-m1 $d/b; git -C $d/b checkout -q catalog-m1; jq ".packages[0].version = .version" $d/b/server.json > $d/b/s.tmp; mv $d/b/s.tmp $d/b/server.json; if (cd $d/b && bash $K/scripts/provider_scaffold.sh --check); then echo "server.json drift not caught"; exit 1; fi'`

**AC-005 — Статический пробник: glama, server.json, mcpb/manifest.json, release.yml, Dockerfile пилота.**
`bash -c 'set -e; echo "147e0e9e0f8dbced0f1d23bdf36c1cdff4c689144ae6231086d7d010f601fd5b  specs/checks/catalog_check.py" | sha256sum -c -; python3 -I specs/checks/catalog_check.py static /home/deploy/exec-clones/s3sel-catalog-m1'`

**AC-006 — Рендер не привязан к Selectel: копия beget после рендера проходит пробник, повторный рендер идемпотентен.**
`bash -c 'set -e; K=$PWD; echo "147e0e9e0f8dbced0f1d23bdf36c1cdff4c689144ae6231086d7d010f601fd5b  specs/checks/catalog_check.py" | sha256sum -c -; d=$(mktemp -d); git clone -q /home/deploy/github/beget-s3-mcp-ai-cli $d/beget; cd $d/beget; bash $K/scripts/provider_scaffold.sh; git add -A; git -c user.name=t -c user.email=t@t commit -qm render; bash $K/scripts/provider_scaffold.sh; test -z "$(git status --porcelain -- . ":(exclude)report.json" ":(exclude)report-blocked.md")"; bash $K/scripts/provider_scaffold.sh --check; python3 -I $K/specs/checks/catalog_check.py static $d/beget; grep -q "beget-s3-mcp-ai-cli" .github/workflows/release.yml; ! grep -rq -i selectel glama.json Dockerfile server.json .github/workflows/release.yml mcpb/manifest.json'`

**AC-007 — Полный сьют селектела зелёный (go test/vet, lint, conformance, smoke, мутации, goreleaser snapshot, actionlint) и goreleaser check.**
`bash -c 'set -e; cd /home/deploy/exec-clones/s3sel-catalog-m1; bash scripts/verify.sh; docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp -v "$PWD:/src:ro" -w /src goreleaser/goreleaser:v2.18.3 check'`

**AC-008 — Сборка .mcpb snapshot: 6 бандлов, манифесты, инструменты = all.golden, checksums дописаны с сохранением чужих строк.**
`bash -c 'set -e; K=$PWD; echo "147e0e9e0f8dbced0f1d23bdf36c1cdff4c689144ae6231086d7d010f601fd5b  specs/checks/catalog_check.py" | sha256sum -c -; cd /home/deploy/exec-clones/s3sel-catalog-m1; VERSION=0.0.0-snapshot bash scripts/build-mcpb.sh; line="$(printf "%064d" 0)  selectel-s3_0.0.0-snapshot_linux_amd64.tar.gz"; printf "%s\n" "$line" > dist-mcpb/checksums.txt; bash scripts/mcpb-checksums.sh dist-mcpb dist-mcpb/checksums.txt; head -1 dist-mcpb/checksums.txt | grep -qxF "$line"; python3 -I $K/specs/checks/catalog_check.py mcpb . dist-mcpb 0.0.0-snapshot dist-mcpb/checksums.txt'`

**AC-009 — Образ пилота: LABEL = name из server.json, initialize и tools/list без ключей и без сети.**
`bash -c 'set -e; echo "147e0e9e0f8dbced0f1d23bdf36c1cdff4c689144ae6231086d7d010f601fd5b  specs/checks/catalog_check.py" | sha256sum -c -; docker build -q -t s3sel-catalog-m1:acc /home/deploy/exec-clones/s3sel-catalog-m1 >/dev/null; python3 -I specs/checks/catalog_check.py image /home/deploy/exec-clones/s3sel-catalog-m1 s3sel-catalog-m1:acc'`

**AC-010 — Сборщик .mcpb отказывает без VERSION и на необязательном поле без default.**
`bash -c 'set -e; d=$(mktemp -d); git clone -q /home/deploy/exec-clones/s3sel-catalog-m1 $d/s; cd $d/s; git checkout -q catalog-m1; if bash scripts/build-mcpb.sh > $d/out1 2>&1; then echo "no VERSION accepted"; exit 1; fi; grep -q "VERSION" $d/out1; jq "del(.user_config.endpoint.default)" mcpb/manifest.json > m.tmp; mv m.tmp mcpb/manifest.json; if VERSION=0.0.1 bash scripts/build-mcpb.sh > $d/out2 2>&1; then echo "missing default accepted"; exit 1; fi; grep -q "endpoint" $d/out2; test ! -e dist-mcpb/selectel-s3_0.0.1_linux_amd64.mcpb'`

**AC-011 — В отрендеренных файлах пилота не осталось плейсхолдеров.**
`bash -c 'cd /home/deploy/exec-clones/s3sel-catalog-m1 && test -s glama.json && test -s Dockerfile && test -s server.json && test -s .github/workflows/release.yml && test -s mcpb/manifest.json && test -s scripts/build-mcpb.sh && if grep -rn "@@[A-Z_]*@@" glama.json Dockerfile server.json .github/workflows/release.yml mcpb/manifest.json scripts/build-mcpb.sh; then exit 1; fi'`
