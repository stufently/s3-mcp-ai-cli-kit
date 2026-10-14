# Раскатка каталожной обвязки: cloudru, vkcloud, yandex (веха m2b2)

- Репозитории: `s3-mcp-ai-cli-kit` (только инструмент и спека) и три провайдера: cloudru, vkcloud, yandex.
  Дата составления 14.10.2026.
- База провайдеров — `main` на 14.10.2026, у всех трёх «Record fresh Docker installation checks»;
  таблица ниже. Kit — `main` на момент запуска, где эта спека уже закоммичена (с вехой 1 —
  `f7fd5c4` «Add provider catalog scaffold» — или новее); kit-клон в этой вехе не меняется.
- Исполнитель: `auto` (выбор лаунчера). Мутации/зонды потом гоняет противоположный исполнитель.
- Критериев: 8. Парная веха `catalog-m2b1` делает то же для beget, mws, timeweb.

## Где работать

Клоны созданы постановщиком `make_clone.sh`, push во всех закрыт:

| Репо | Клон | BASE (main) |
|---|---|---|
| kit | `/home/deploy/exec-clones/s3kit-catalog-m2b2` | HEAD клона (спека уже в нём, tracked) |
| `cloudru` | `/home/deploy/exec-clones/s3cloudru-catalog-m2` | `9fec15c645e97b1ce2d616137977e16b7f004955` |
| `vkcloud` | `/home/deploy/exec-clones/s3vkcloud-catalog-m2` | `d3e53cdba81c57d4b1ada9111d8dbaa0403588ce` |
| `yandex` | `/home/deploy/exec-clones/s3yandex-catalog-m2` | `9516fcae54470c2d9086e4be1572966e8e071835` |

В КАЖДОМ клоне провайдера создать ветку `catalog-m2` от BASE и коммитить туда. В kit-клоне
ничего не коммитить и не менять (кроме untracked `report.json`/`report-blocked.md`). Живые
деревья `~/github/*` не трогать (читать можно). **Push в origin запрещён во всех клонах, теги
не создавать** — работу заберёт постановщик через `git fetch` из клонов.

## Задача и почему

Веха 1 сделала в kit шаблон каталожной обвязки и рендерер `scripts/provider_scaffold.sh`
(glama.json, Desktop Extension `.mcpb`, attestation, публикация в MCP Registry, LABEL и
заглушка ключей в образе) и раскатала его на Selectel (`selectel-s3-mcp-ai-cli` main
`832825a`). Эта веха раскатывает ровно тот же рендер на cloudru, vkcloud, yandex. Код kit не меняется:
всё, что нужно, — прогнать рендер, дописать CHANGELOG и доказать, что каждый провайдер
проходит ту же приёмку, что пилот.

## Что проверено вживую, а что предположение

- Постановщик прогнал рендер на свежих копиях всех шести провайдеров с kit `f7fd5c4`:
  рендер rc 0, `--check` rc 0, `catalog_check.py static` → `OK: static`; меняются ровно
  `.dockerignore`, `.gitignore`, `Dockerfile` (+5 строк: заглушка ключей и два LABEL),
  `.github/workflows/release.yml`, `server.json` (identifier с тегом, без package version),
  появляются `glama.json`, `mcpb/manifest.json`, `scripts/build-mcpb.sh`,
  `scripts/mcpb-checksums.sh`. В отрендеренных файлах нет имён чужих провайдеров.
- 🚨 `testdata/tools/*.golden` есть ТОЛЬКО у Selectel (наследие до выноса kit). У cloudru, vkcloud, yandex
  каталога `testdata/tools/` нет, а `build-mcpb.sh` и пробник (`mcpb` — `all.golden`,
  `image` — `read.golden`) без них падают. Наборы инструментов у провайдеров РАЗНЫЕ (kit
  0.1.1 отключает bucket-инструменты у console-only профилей): у beget постановщик снял
  10 инструментов без ключей/ALLOW и 18 с `ALLOW=write,delete,admin` (у Selectel 13 и 31).
  Поэтому golden-списки снимаются с образа самого провайдера — это снимок поведения, а не
  независимый оракул; сверку с `features` профиля делает постановщик при приёмке.
  Постановщик вычислил ожидание из реестра инструментов kit v0.1.0 (его используют все три,
  `go.mod`) и `features` профилей: у cloudru, vkcloud, yandex — по 14 (read) и 32 (all). Тот
  же расчёт совпал со снятыми golden у beget, mws, timeweb и selectel. Образ дал другие
  числа — не подгоняй, стоп по контракту с обоими списками в `report-blocked.md`.
- `binary` у всех — `<id>-s3`; `profile.yaml` и `server.json` в ASCII-наборе рендерера.
- `scripts/verify.sh` провайдера = `bash scripts/kit.sh verify` (kit по тегу из `ci.yml`,
  сеть нужна); для пилота этот сьют после рендера зелёный (критерий вехи 1).
- `CHANGELOG.md` провайдеров начинается с `## Unreleased`, пункты — строки `- …`. Запись
  пилота: `- Add catalog metadata, Desktop Extension bundles and Registry release jobs.`
- Docker-образы `golang:1.27.2`, `goreleaser/goreleaser:v2.18.3`, `rhysd/actionlint:1.7.12`,
  `node:24.21.0-slim` на хосте есть. Все `docker run` — под `-u "$(id -u):$(id -g)"`.
- ПРЕДПОЛОЖЕНИЕ: `verify.sh` каждого из трёх зелёный на нетронутом main (CI main зелёный, но
  локально на этих трёх постановщик его не гонял).

## Что сделать

Для каждого из cloudru, vkcloud, yandex, в его клоне, на ветке `catalog-m2`:

1. `bash /home/deploy/exec-clones/s3kit-catalog-m2b2/scripts/provider_scaffold.sh` из корня клона. Руками ничего из
   отрендеренного не править: нужна правка — это дефект kit, стоп по контракту.
2. Снять golden-списки инструментов с образа провайдера (проверено постановщиком на beget):
   ```bash
   docker build -q -t s3$p-catalog-m2:golden .
   req='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"golden","version":"0"}}}
   {"jsonrpc":"2.0","method":"notifications/initialized"}
   {"jsonrpc":"2.0","id":2,"method":"tools/list"}'
   mkdir -p testdata/tools
   (printf '%s\n' "$req"; sleep 3) | docker run -i --rm --network none s3$p-catalog-m2:golden > /var/tmp/$p-read.json
   (printf '%s\n' "$req"; sleep 3) | docker run -i --rm --network none -e <ENV_PREFIX>ALLOW=write,delete,admin s3$p-catalog-m2:golden > /var/tmp/$p-all.json
   jq -r 'select(.id==2) | .result.tools[].name' /var/tmp/$p-read.json | LC_ALL=C sort > testdata/tools/read.golden
   jq -r 'select(.id==2) | .result.tools[].name' /var/tmp/$p-all.json | LC_ALL=C sort > testdata/tools/all.golden
   ```
   (`<ENV_PREFIX>` — `env_prefix` из `internal/provider/profile.yaml`, например `BEGET_S3_`;
   `sleep` держит stdin открытым, иначе сервер выходит до ответа.) Файлы — по имени на
   строку, C-сортировка, без дублей; пустой результат — стоп по контракту.
3. Добавить ОДНУ строку первым пунктом раздела `## Unreleased` `CHANGELOG.md` — ПОСЛЕ
   пустой строки под заголовком, вплотную к прежним пунктам (как у пилота Selectel):
   ```
   ## Unreleased

   - Add catalog metadata, Desktop Extension bundles and Registry release jobs.
   - Add provider-specific Russian/English discovery text, …
   ```
4. Закоммитить (≤50 символов, imperative, без подписей и Co-Authored-By), например
   `Add catalog metadata and release jobs`.

## Не трогать

- Kit-клон целиком (никаких правок и коммитов), включая `specs/checks/catalog_check.py` и
  эту спеку.
- В провайдерах — всё, кроме результата рендера, двух golden-файлов и CHANGELOG: Go-код, `go.mod/go.sum`,
  `.goreleaser.yaml`, `ci.yml`, `profile.yaml`, прочий `testdata/`, README, docs, skills.
- Никаких тегов, релизов, `git push`, `gh release`, публикаций в ghcr/Registry, `docker push`.
- Ожидаемые изменения в каждом провайдере от его BASE, РОВНО: `glama.json`, `Dockerfile`, `server.json`, `.github/workflows/release.yml`, `mcpb/manifest.json`, `scripts/build-mcpb.sh`, `scripts/mcpb-checksums.sh`, `.gitignore`, `.dockerignore`, `CHANGELOG.md`, `testdata/tools/read.golden`, `testdata/tools/all.golden`.

## Разрешения

Чтение всех репо, запуск рендера и сьютов, Docker под своим uid, сеть для Go-модулей, npm и
kit по тегу, локальные коммиты в клонах провайдеров.

## Авторевью

В этой вехе исполнитель ревьюеров НЕ зовёт (перекрёстное авторевью не применяется, отчёт —
старой схемы — без поля версии схемы, только `criteria`). Причина: дифф каждого провайдера — машинный вывод
рендерера, уже прошедшего ревью и мутации в вехе 1, а критерий AC-003 доказывает
байтовое совпадение с рендером. Независимое чтение диффов, сверку с пилотом и мутации
проводит постановщик после `report.json`.

## Контракт на невыполнимое

Рендер падает или `static`/`image`/`mcpb` красные из-за содержимого провайдера; полный сьют
красный на нетронутом main; нужен файл вне списка; сеть/Docker не дают выполнить команду —
остановись, запиши причину в `report-blocked.md` в корне kit-клона и в отчёт (`blocked`,
`"rc": null`, дословная ошибка). Править kit, пробник, шаблоны или Go-код, обходить
несовместимость (подменять окружение, глушить коды возврата) запрещено.

## Стыки с соседними вехами

Парная веха раскатывает то же на beget, mws, timeweb; веха самотеста kit (2a) меняет только тесты kit и
на рендер не влияет. После этой вехи постановщик сливает провайдеров по одному PR на репо;
теги и релизы — решение владельца после живой проверки в облаках.

## Контракт отчёта

`report.json` в корне kit-клона `/home/deploy/exec-clones/s3kit-catalog-m2b2`, untracked:
`{"criteria": [{"id": "AC-001", "status": "pass|fail|blocked", "command": "<команда из спеки>", "rc": 0, "note": "…"}]}` —
ровно 8 записей, по одной на критерий; `command` — дословно из спеки; у `blocked`
`"rc": null` и дословная ошибка.

## Критерии приёмки

Команды запускаются из корня kit-клона `/home/deploy/exec-clones/s3kit-catalog-m2b2`.

**AC-001 — Kit-клон не изменён, дерево чистое.**
`bash -c 'set -e; test -z "$(git diff --name-only origin/main HEAD)"; test -z "$(git status --porcelain -- . ":(exclude)report.json" ":(exclude)report-blocked.md")"'`

**AC-002 — В каждом провайдере изменены только разрешённые пути, CHANGELOG дополнен, всё закоммичено в catalog-m2.**
`bash -c 'set -e; for pb in cloudru:9fec15c645e97b1ce2d616137977e16b7f004955 vkcloud:d3e53cdba81c57d4b1ada9111d8dbaa0403588ce yandex:9516fcae54470c2d9086e4be1572966e8e071835; do p=${pb%%:*}; B=${pb#*:}; cd /home/deploy/exec-clones/s3$p-catalog-m2; test "$(git branch --show-current)" = catalog-m2; git diff --check $B HEAD; git diff --quiet $B HEAD -- . ":(exclude)glama.json" ":(exclude)Dockerfile" ":(exclude)server.json" ":(exclude).github/workflows/release.yml" ":(exclude)mcpb/manifest.json" ":(exclude)scripts/build-mcpb.sh" ":(exclude)scripts/mcpb-checksums.sh" ":(exclude).gitignore" ":(exclude).dockerignore" ":(exclude)CHANGELOG.md" ":(exclude)testdata/tools/read.golden" ":(exclude)testdata/tools/all.golden"; test -n "$(git diff $B HEAD -- CHANGELOG.md | grep "^+- ")"; git ls-files --error-unmatch glama.json mcpb/manifest.json scripts/build-mcpb.sh scripts/mcpb-checksums.sh testdata/tools/read.golden testdata/tools/all.golden >/dev/null; test -z "$(git status --porcelain -- . ":(exclude)report.json" ":(exclude)report-blocked.md")"; done'`

**AC-003 — Каждый провайдер совпадает с рендером, а check ловит дрейф release.yml и server.json.**
`bash -c 'set -e; K=$PWD; for p in cloudru vkcloud yandex; do cd /home/deploy/exec-clones/s3$p-catalog-m2; bash $K/scripts/provider_scaffold.sh --check; d=$(mktemp -d); git clone -q -b catalog-m2 $PWD $d/a; echo "# drift" >> $d/a/.github/workflows/release.yml; if (cd $d/a && bash $K/scripts/provider_scaffold.sh --check); then echo "$p: release.yml drift not caught"; exit 1; fi; git clone -q -b catalog-m2 $PWD $d/b; jq ".packages[0].version = .version" $d/b/server.json > $d/b/s.tmp; mv $d/b/s.tmp $d/b/server.json; if (cd $d/b && bash $K/scripts/provider_scaffold.sh --check); then echo "$p: server.json drift not caught"; exit 1; fi; done'`

**AC-004 — Статический пробник зелёный, нет плейсхолдеров и чужих имён, golden-списки отсортированы и вложены.**
`bash -c 'set -e; K=$PWD; echo "147e0e9e0f8dbced0f1d23bdf36c1cdff4c689144ae6231086d7d010f601fd5b  specs/checks/catalog_check.py" | sha256sum -c -; for p in cloudru vkcloud yandex; do cd /home/deploy/exec-clones/s3$p-catalog-m2; python3 -I $K/specs/checks/catalog_check.py static $PWD; case $p in cloudru) o="selectel|beget|mws|timeweb|vkcloud|yandex";; vkcloud) o="selectel|beget|mws|timeweb|cloudru|yandex";; yandex) o="selectel|beget|mws|timeweb|cloudru|vkcloud";; esac; if grep -rn "@@[A-Z_]*@@" glama.json Dockerfile server.json .github/workflows/release.yml mcpb/manifest.json scripts/build-mcpb.sh; then exit 1; fi; if grep -rliE "$o" glama.json Dockerfile server.json .github/workflows/release.yml mcpb/manifest.json; then exit 1; fi; grep -q "$p-s3-mcp-ai-cli" .github/workflows/release.yml; LC_ALL=C sort -c -u testdata/tools/read.golden; LC_ALL=C sort -c -u testdata/tools/all.golden; test -s testdata/tools/read.golden; test -z "$(LC_ALL=C comm -23 testdata/tools/read.golden testdata/tools/all.golden)"; done'`

**AC-005 — Полный сьют каждого провайдера зелёный и goreleaser check.**
`bash -c 'set -e; for p in cloudru vkcloud yandex; do cd /home/deploy/exec-clones/s3$p-catalog-m2; bash scripts/verify.sh; docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp -v "$PWD:/src:ro" -w /src goreleaser/goreleaser:v2.18.3 check; done'`

**AC-006 — Сборка mcpb snapshot у каждого: 6 бандлов, инструменты = all.golden, checksums дописаны.**
`bash -c 'set -e; K=$PWD; echo "147e0e9e0f8dbced0f1d23bdf36c1cdff4c689144ae6231086d7d010f601fd5b  specs/checks/catalog_check.py" | sha256sum -c -; for p in cloudru vkcloud yandex; do cd /home/deploy/exec-clones/s3$p-catalog-m2; VERSION=0.0.0-snapshot bash scripts/build-mcpb.sh; line="$(printf "%064d" 0)  $p-s3_0.0.0-snapshot_linux_amd64.tar.gz"; printf "%s\n" "$line" > dist-mcpb/checksums.txt; bash scripts/mcpb-checksums.sh dist-mcpb dist-mcpb/checksums.txt; head -1 dist-mcpb/checksums.txt | grep -qxF "$line"; python3 -I $K/specs/checks/catalog_check.py mcpb . dist-mcpb 0.0.0-snapshot dist-mcpb/checksums.txt; done'`

**AC-007 — Образ каждого: LABEL = name из server.json, initialize и tools/list без ключей и без сети.**
`bash -c 'set -e; K=$PWD; echo "147e0e9e0f8dbced0f1d23bdf36c1cdff4c689144ae6231086d7d010f601fd5b  specs/checks/catalog_check.py" | sha256sum -c -; for p in cloudru vkcloud yandex; do cd /home/deploy/exec-clones/s3$p-catalog-m2; docker build -q -t s3$p-catalog-m2:acc . >/dev/null; python3 -I $K/specs/checks/catalog_check.py image $PWD s3$p-catalog-m2:acc; done'`

**AC-008 — Сборщик mcpb у каждого отказывает без VERSION и на поле без default.**
`bash -c 'set -e; for p in cloudru vkcloud yandex; do cd /home/deploy/exec-clones/s3$p-catalog-m2; d=$(mktemp -d); git clone -q -b catalog-m2 $PWD $d/s; cd $d/s; if bash scripts/build-mcpb.sh > $d/out1 2>&1; then echo "$p: no VERSION accepted"; exit 1; fi; grep -qx "VERSION is required" $d/out1; jq "del(.user_config.endpoint.default)" mcpb/manifest.json > m.tmp; mv m.tmp mcpb/manifest.json; if VERSION=0.0.1 bash scripts/build-mcpb.sh > $d/out2 2>&1; then echo "$p: missing default accepted"; exit 1; fi; grep -qx endpoint $d/out2; test ! -e dist-mcpb/$p-s3_0.0.1_linux_amd64.mcpb; done'`
