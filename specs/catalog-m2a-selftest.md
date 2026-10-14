# Самотест каталожной обвязки в kit (веха 2a)

- Репозиторий `s3-mcp-ai-cli-kit`, дата 14.10.2026.
- BASE_SHA: `f7fd5c4a632502025b4079274c6896a51f068471` («Add provider catalog scaffold») —
  `main` после мержа вехи 1, коммит, с которого снят клон. Поверх него в клоне ОДИН коммит
  постановщика (эта спека и пробник `specs/checks/selftest_mutants.py`); левая граница
  диффа ревью и `base_sha` отчёта — именно BASE_SHA.
- Исполнитель: `auto` (выбор лаунчера). Мутации по новым тестам потом гоняет
  ПРОТИВОПОЛОЖНЫЙ исполнитель отдельным прогоном.
- Критериев: 6.

## Где работать

Клон `/home/deploy/exec-clones/s3kit-catalog-m2a` (создан `make_clone.sh`, push закрыт).
Создать ветку `catalog-m2a` от текущего HEAD клона (коммит постановщика) и коммитить туда.
Живые деревья `~/github/*` не трогать (читать можно). **Push в origin запрещён, теги не
создавать** — работу заберёт постановщик через `git fetch` из клона.

Что положил постановщик (закоммичено поверх BASE, НЕ редактировать):

| Файл | sha256 |
|---|---|
| `specs/catalog-m2a-selftest.md` | (эта спека) |
| `specs/checks/selftest_mutants.py` | `952ac6d018e1f69b9090c30dc68dbb99ba45a0942533e372ca3dc1ea1f508ab8` |

## Задача и почему

Веха 1 добавила в kit рендерер `scripts/provider_scaffold.sh`, сборщик
`scripts/build-mcpb.sh` и пробник приёмки `specs/checks/catalog_check.py`, но ни одного
теста в репо: их проверяли только критерии спеки. Мутационный прогон приёмки (28 мутантов)
оставил 13 выживших, 12 — реальные дыры: бит исполнения в `--check`, кавычка в
`display_name`, неподставленный `@@X@@`, закомментированное правило `# dist-mcpb`,
небезопасный `VERSION`, сообщение `VERSION is required`, отсутствие `all.golden`,
`endpoint.default`, лишний job, `license`, `transport`, исполняемость скриптов в пробнике.
Тринадцатый (A11, фильтр строк с `#` в правилах ignore) эквивалентен: правило, начинающееся
с `#`, не может равняться `dist-mcpb` после `strip("/")`.

Нужен самотест `scripts/catalog_selftest.sh`, вызываемый из `scripts/verify.sh` (то есть из
CI kit), который ловит все 27 неэквивалентных мутантов вехи 1 — включая 15 уже убитых
критериями спеки: критерии спеки в CI не живут, тест должен.

Боевой код вехи 1 НЕ меняется: мутации пробника накладываются по точным строкам этих
файлов, и их sha256 пробник сверяет с BASE.

## Что проверено вживую, а что предположение

- `scripts/verify.sh` kit (14 строк): go build/vet/test, golangci-lint, conformance, smoke,
  mutation gate, actionlint — всё в Docker; ветка `if [[ -f internal/provider/profile.yaml ]]`
  в kit не исполняется. CI kit (`.github/workflows/ci.yml`) — `bash scripts/verify.sh` на
  `ubuntu-latest`; на раннере есть `python3`, `jq`, `git`.
- `provider_scaffold.sh` запускается из корня провайдера (нужны `internal/provider/profile.yaml`
  и `server.json`), корень kit берёт по пути самого скрипта (`dirname BASH_SOURCE/..`);
  без флага рендерит `glama.json`, `Dockerfile`, `.github/workflows/release.yml`,
  `mcpb/manifest.json`, копирует `scripts/build-mcpb.sh` и `scripts/mcpb-checksums.sh`
  (chmod 0755), нормализует `server.json` через `jq`, дописывает `/dist-mcpb/` в `.gitignore`
  и `dist-mcpb` в `.dockerignore`; отказ на значении вне `[A-Za-z0-9 ._,:/()-]` пишет в stderr
  `provider_scaffold: DISPLAY_NAME contains characters outside …` ДО записи файлов;
  `--check` печатает расходящиеся пути по одному на строку и выходит 1; исполняемость
  сравнивается только по биту владельца (`st_mode & 0o100`).
- `build-mcpb.sh`: первым делом `cd "$(git rev-parse --show-toplevel)"` (значит, каталог
  провайдера обязан быть git-репо; коммиты не нужны); без `VERSION` — строка
  `VERSION is required` в stderr, rc 1; токен вне `^[0-9A-Za-z][0-9A-Za-z._+-]*$` —
  `VERSION=<…> is not a safe version token`; нет `profile.yaml`/`mcpb/manifest.json`/
  `testdata/tools/all.golden` — строка с `all.golden`; необязательное поле `user_config` без
  `default` — имя поля отдельной строкой в stderr, rc 1. Всё это ДО первого вызова `docker`.
  Перед Docker скрипт делает `mkdir -p "$HOME/.cache/sel-s3-go" "$HOME/.cache/sel-s3-mcpb-npm"`.
- `catalog_check.py static <dir>` печатает `FAIL: <сообщение>` и выходит 1; дословные
  сообщения, на которые опираются случаи ниже, взяты из самого файла (sha256
  `147e0e9e0f8dbced0f1d23bdf36c1cdff4c689144ae6231086d7d010f601fd5b`).
- Фикстура: пять файлов селектела ДО обвязки, коммит
  `638376907b7cfdf6b7aee5f20db7d2be4f81a8d1` репо `~/github/selectel-s3-mcp-ai-cli`
  (`git -C ~/github/selectel-s3-mcp-ai-cli show 6383769…:<путь>`). Рендер из них проходит
  `static` (проверено рендером на копии).
- Пробник `selftest_mutants.py` проверен постановщиком на двух зондах: эталонный самотест
  (21 случай по таблице ниже) — baseline зелёный, все 27 мутантов убиты своими случаями, ~1 мин;
  самотест, печатающий `ok` на всё, — 27 выживших, rc 1.

## Что сделать

1. **Фикстура** `testdata/catalog-provider/` — ровно пять файлов, байт-в-байт из селектела
   на `6383769…`: `internal/provider/profile.yaml`, `server.json`, `.gitignore`,
   `.dockerignore`, `testdata/tools/all.golden`. Больше ничего в каталоге.
2. **`scripts/catalog_selftest.sh`** (bash, `#!/usr/bin/env bash`, shellcheck чист):
   - корень kit — по пути самого скрипта; все вызовы — `$kit/scripts/provider_scaffold.sh`,
     `$kit/specs/checks/catalog_check.py` (через `python3 -I`), а `build-mcpb.sh` — копией,
     которую рендер положил в каталог провайдера (`bash scripts/build-mcpb.sh`);
   - каждый случай работает в СВОЕЙ свежей копии фикстуры во временном каталоге
     (`mktemp -d`, уборка через `trap … EXIT`), копия — `git init -q`; дерево kit самотест не
     меняет, Docker не зовёт, в настоящий `$HOME` не пишет;
   - для случаев `build-*`: каталог-заглушка с исполняемым `docker` (пишет маркер в свой
     временный каталог и `exit 97`) первым в `PATH`, `HOME` — временный каталог;
   - вывод: по ОДНОЙ строке на случай — `ok <case>` или `FAIL <case>: <причина>`; случаи
     изолированы (падение одного не прерывает остальные, `set -e` не валит скрипт); код
     возврата 0 тогда и только тогда, когда все случаи `ok`;
   - случаи — ровно эти 21 имя (пробник ищет их дословно):

| Случай | Что делает и что требует |
|---|---|
| `render-clean` | рендер фикстуры rc 0; затем `--check` rc 0; `static` rc 0; оба скрипта в `scripts/` исполняемы; в отрендеренных файлах нет `@@` |
| `check-drift-release` | после рендера дописать строку в `.github/workflows/release.yml`; `--check` rc≠0 и печатает ровно этот путь строкой |
| `check-drift-server-version` | после рендера вернуть `.packages[0].version = .version` в `server.json`; `--check` rc≠0, строка `server.json` |
| `check-exec-bit` | после рендера `chmod 0644 scripts/build-mcpb.sh`; `--check` rc≠0, строка `scripts/build-mcpb.sh` |
| `check-mode-0775` | после рендера `chmod 0775` обоих скриптов; `--check` rc 0 |
| `reject-unsafe-value` | `display_name` с двойной кавычкой; рендер rc≠0, stderr содержит `DISPLAY_NAME`, `glama.json` не создан |
| `reject-placeholder` | копия kit (`scripts/` и `templates/`) во временный каталог, в один шаблон дописать `@@UNKNOWN@@`; рендер этой копией rc≠0, stderr содержит `unreplaced placeholder`, `glama.json` не создан |
| `commented-ignore` | `.gitignore` = одна строка `# dist-mcpb`; рендер rc 0; `git check-ignore -q dist-mcpb/probe` rc 0 |
| `build-no-version` | после рендера, `VERSION` снят из окружения; rc≠0, в stderr есть строка, РАВНАЯ `VERSION is required`, `docker` не вызван |
| `build-unsafe-version` | `VERSION='1;touch x'`; rc≠0, stderr содержит `not a safe version token`, `docker` не вызван, файла `x` нет |
| `build-missing-golden` | удалить `testdata/tools/all.golden`, `VERSION=0.0.1`; rc≠0, stderr содержит `all.golden`, `docker` не вызван |
| `build-missing-default` | удалить `.user_config.endpoint.default` из `mcpb/manifest.json`, `VERSION=0.0.1`; rc≠0, в stderr строка, РАВНАЯ `endpoint`, `docker` не вызван, `*.mcpb` нет |
| `build-reaches-docker` | нетронутый рендер, `VERSION=0.0.1`; заглушка `docker` вызвана (положительный контроль: предпроверки пропускают правильный вход) |
| `static-package-version` | `.packages[0].version = .version`; `static` rc≠0, вывод содержит `OCI package must not have version` |
| `static-identifier` | тег отрезан от `.packages[0].identifier`; вывод содержит `OCI identifier must be` |
| `static-label` | из `Dockerfile` удалена строка с `io.modelcontextprotocol.server.name`; вывод содержит `io.modelcontextprotocol.server.name` |
| `static-endpoint-default` | `.user_config.endpoint.default = "https://wrong.invalid"`; вывод содержит `user_config.endpoint default must be` |
| `static-extra-job` | в `release.yml` добавлен пятый job `unexpected` (при сохранении четырёх); вывод содержит `jobs must be exactly` |
| `static-license` | `.license = "Apache-2.0"` в манифесте; вывод содержит `manifest license must be MIT` |
| `static-transport` | `.packages[0].transport = {"type": "streamable-http"}`; вывод содержит `transport stdio` |
| `static-exec-bit` | `chmod 0644 scripts/build-mcpb.sh`; вывод содержит `scripts/build-mcpb.sh must exist and be executable` |

   Каждый отрицательный случай проверяет И код возврата, И свою причину (строку выше):
   падение «не по той причине» — это `FAIL` случая. Правки JSON — `jq`, не `sed`.
3. **`scripts/verify.sh`** — добавить ровно строку `bash "$kit/scripts/catalog_selftest.sh"`
   (без условия, после строки с `mutation_gate_test.go`). Остальное не трогать.
4. **`CHANGELOG.md`** — одна запись в раздел `## 2026-10-14` (или новый раздел с датой
   коммита): самотест каталожной обвязки.

## Не трогать

- `scripts/provider_scaffold.sh`, `scripts/build-mcpb.sh`, `scripts/mcpb-checksums.sh`,
  `templates/**`, `specs/checks/catalog_check.py`, `specs/checks/selftest_mutants.py`, эту
  спеку, весь Go-код, `go.mod/go.sum`, `.github/**`, README, docs, skills.
  Нашёл дефект в боевом скрипте — НЕ чини, опиши в `report.json` (`note`) и в
  `report-blocked.md`, если он мешает критерию.
- Никаких тегов, релизов, `git push`, `gh release`, публикаций, `docker push`.
- Ожидаемые изменения от BASE_SHA, РОВНО: `scripts/catalog_selftest.sh`,
  `scripts/verify.sh`, `testdata/catalog-provider/**`, `CHANGELOG.md`,
  `specs/catalog-m2a-selftest.md`, `specs/checks/selftest_mutants.py` (последние два —
  коммит постановщика, исполнитель их не меняет).

## Разрешения

Чтение всех репо, правка перечисленных файлов, Docker под своим uid (`-u "$(id -u):$(id -g)"`),
сеть для Go-модулей, локальные коммиты в клоне (≤50 символов, imperative, без подписей и
Co-Authored-By).

## Критерии приёмки

Команды запускаются из корня клона.

**AC-001 — Изменены только разрешённые пути, ветка catalog-m2a, дерево чистое.**
`bash -c 'set -e; B=f7fd5c4a632502025b4079274c6896a51f068471; test "$(git branch --show-current)" = catalog-m2a; git diff --check $B HEAD; git diff --quiet $B HEAD -- . ":(exclude)scripts/catalog_selftest.sh" ":(exclude)scripts/verify.sh" ":(exclude)testdata/catalog-provider" ":(exclude)CHANGELOG.md" ":(exclude)specs/catalog-m2a-selftest.md" ":(exclude)specs/checks/selftest_mutants.py"; test -n "$(git diff --name-only $B HEAD -- CHANGELOG.md)"; git ls-files --error-unmatch scripts/catalog_selftest.sh >/dev/null; test -z "$(git status --porcelain -- . ":(exclude)report.json" ":(exclude)report-blocked.md")"'`

**AC-002 — Фикстура ровно из пяти файлов селектела до обвязки, байт-в-байт.**
`bash -c 'set -e; cd testdata/catalog-provider; test "$(git ls-files . | LC_ALL=C sort | tr "\n" " ")" = ".dockerignore .gitignore internal/provider/profile.yaml server.json testdata/tools/all.golden "; printf "%s\n" "e61f6fd532879fac64185608f2763ab0522acf3b36eb48072446d796f4fa7bc0  internal/provider/profile.yaml" "3498500278e9df4f74fac93913f5b2c6590dd5fd0ee4212cc437f83ef3cee2e9  server.json" "4eb2fdf41c89473d732df35719e210046ecf837293468bf74fe0a872b831070c  .gitignore" "21595ab5f0d4924fb5ee08f189442c58c6a792a5c034a28df987ffe82edd698f  .dockerignore" "1c9e193705319c26d1c80756b6eb399697a08b0dde185014ccb5ce120fb47ff1  testdata/tools/all.golden" > "$(git rev-parse --git-dir)/fixture.sha256"; sha256sum -c --quiet "$(git rev-parse --git-dir)/fixture.sha256"'`

**AC-003 — Shellcheck чист на самотесте.**
`bash -c 'docker run --rm -u "$(id -u):$(id -g)" -v "$PWD:/mnt:ro" -w /mnt koalaman/shellcheck:v0.11.0 scripts/catalog_selftest.sh'`

**AC-004 — Самотест зелёный, 21 случай ok, без Docker, без записи в HOME и в дерево.**
`bash -c 'set -e; d=$(mktemp -d); mkdir $d/bin $d/home; printf "#!/bin/sh\ntouch %s/real-docker-called\nexit 1\n" "$d" > $d/bin/docker; chmod +x $d/bin/docker; env HOME=$d/home PATH="$d/bin:$PATH" bash scripts/catalog_selftest.sh > $d/out; test "$(grep -c "^ok " $d/out)" = 21; test -z "$(grep "^FAIL" $d/out)"; test ! -e $d/real-docker-called; test -z "$(ls -A $d/home)"; test -z "$(git status --porcelain -- . ":(exclude)report.json" ":(exclude)report-blocked.md")"'`

**AC-005 — Пробник постановщика: все 27 неэквивалентных мутантов вехи 1 убиты своими случаями.**
`bash -c 'set -e; echo "952ac6d018e1f69b9090c30dc68dbb99ba45a0942533e372ca3dc1ea1f508ab8  specs/checks/selftest_mutants.py" | sha256sum -c -; python3 -I specs/checks/selftest_mutants.py "$PWD"'`

**AC-006 — Самотест подключён к verify.sh, полный verify kit зелёный.**
`bash -c 'set -e; grep -qxF "bash \"\$kit/scripts/catalog_selftest.sh\"" scripts/verify.sh; bash scripts/verify.sh'`

## Контракт отчёта

`report.json` в КОРНЕ клона, untracked, схема v2 (её проверяет `accept_run.py` до запуска
критериев):

```json
{"schema_version": 2,
 "policy_id": "cross-review-v1",
 "handoff_status": "ready",
 "executor": {"backend": "grok|spark|codex", "model": "<точная модель>"},
 "spec_sha256": "<sha256 файла specs/catalog-m2a-selftest.md>",
 "base_sha": "f7fd5c4a632502025b4079274c6896a51f068471",
 "reviewed_sha": "<коммит, отданный на ревью>",
 "final_sha": "<HEAD клона после единственного захода фиксов>",
 "review": {"initial_receipts": [], "verification_receipts": [], "resolutions": []},
 "criteria": [{"id": "AC-001", "status": "pass|fail|blocked",
               "command": "<команда ИЗ ЭТОЙ СПЕКИ, посимвольно>", "rc": 0, "note": "…"}]}
```

Записей в `criteria` ровно 6, по одной на критерий. Поле — `reviewed_sha`, не `review_sha`;
три sha — 40 строчных hex; `final_sha` = HEAD клона; `base_sha → reviewed_sha → final_sha` —
предки друг друга. `command` совпадает с командой критерия ДОСЛОВНО. Квитанции ревью
перечисляются в `review.initial_receipts` / `review.verification_receipts`. Перед сдачей:
`python3 /home/deploy/.claude/skills/executor-milestone/scripts/accept_run.py /home/deploy/exec-clones/s3kit-catalog-m2a --spec /home/deploy/exec-clones/s3kit-catalog-m2a/specs/catalog-m2a-selftest.md --dry-run`
обязан дать код 2 (`validation_only`).

`blocked` — штатный исход, когда среда не даёт выполнить критерий: `"rc": null`, в `command`
команда-улика, в `note` дословная ошибка. Обходить несовместимость (`--no-deps`, `|| true`,
`set +e` в команде критерия, `sudo`, `git push`) ЗАПРЕЩЕНО.

## Контракт на невыполнимое

Противоречие в спеке, невыполнимый критерий, факт, опровергающий раздел «Что проверено»
(сообщение скрипта не то, пробник падает на baseline при честном самотесте, мутант
невозможно убить без правки боевого скрипта) — **остановись и доложи**: `report-blocked.md`
в корне клона с дословной командой, выводом и опровергнутым утверждением. Править пробник,
спеку и боевые скрипты, ослаблять критерии — запрещено.

## Автономное перекрёстное ревью

Действует `cross-review-v1` целиком: `/home/deploy/.claude/skills/executor-milestone/docs/cross-review-v1.md`.
Пара ревьюеров по backend исполнителя: Codex или Spark → `agy` + `grok`; Grok → `codex` + `agy`.
Сам себя не ревьюит никто.

1. Реализация → своя проверка всех AC → коммит: это REVIEW_SHA.
2. Оба ревью параллельно на `BASE_SHA..REVIEW_SHA`, каждое только читает:
   `bash /home/deploy/.claude/skills/executor-milestone/scripts/review_run.sh initial <ревьюер> --clone /home/deploy/exec-clones/s3kit-catalog-m2a --base f7fd5c4a632502025b4079274c6896a51f068471 --range f7fd5c4a632502025b4079274c6896a51f068471..<REVIEW_SHA> --context "S3 kit catalog self-test milestone 2a, read-only"`
   run_id = `s3kit-catalog-m2a-f7fd5c4a6325`; квитанции пишет только `review_run.sh`.
3. Дождаться ОБОИХ, свести находки, по каждой `fixed` / `disproved` / `needs_owner`.
   Один заход исправлений → FINAL_SHA. Затем те же два ревьюера ОДИН раз на
   `REVIEW_SHA..FINAL_SHA` (фаза `verification`, тот же `--base f7fd5c4a632502025b4079274c6896a51f068471`);
   если код после ревью не менялся и споров нет — завершающая проверка пропускается. Второй
   заход исправлений запрещён.
4. Обрезанный вход, оборванный ответ или нет маркера `ВЕРДИКТ:` — `incomplete`, а не «находок
   нет». Один технический повтор незавершённого вызова допустим; исчерпанная квота —
   `blocked`. Эксперименты с процессами, сигналами и tmux — только в Docker с фейками.

## Стыки с соседними вехами

Следующие вехи (раскатка обвязки на шесть провайдеров, две по три репо) рендерят
боевыми скриптами вехи 1, которые здесь не меняются; их спеки лежат рядом в `specs/`.
Самотест обещает: любая будущая правка рендерера, сборщика или пробника, ломающая
перечисленное поведение, краснеет в CI kit.
