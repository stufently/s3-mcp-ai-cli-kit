# Самотест каталожной обвязки: семь выживших мутантов (веха 2c)

- Репозиторий `s3-mcp-ai-cli-kit`, дата 14.10.2026.
- BASE_SHA: `9ab121722e3b93507aa9dc153bc391ffe1f8718c` («Add catalog scaffold self-test») —
  `main` после мержа вехи 2a. Поверх него в клоне ОДИН коммит постановщика (эта спека и
  пробник `specs/checks/selftest_mutants_m2c.py`); левая граница диффа ревью и `base_sha`
  отчёта — именно BASE_SHA.
- Исполнитель: `auto` (выбор лаунчера). Мутации по новым тестам потом гоняет
  ПРОТИВОПОЛОЖНЫЙ исполнитель отдельным прогоном.
- Критериев: 5.

## Где работать

Клон `/home/deploy/exec-clones/s3kit-catalog-m2c` (создан `make_clone.sh`, push закрыт).
Создать ветку `catalog-m2c` от текущего HEAD клона (коммит постановщика) и коммитить туда.
Живые деревья `~/github/*` не трогать (читать можно). **Push в origin запрещён, теги не
создавать** — работу заберёт постановщик через `git fetch` из клона.

Что положил постановщик (закоммичено поверх BASE, НЕ редактировать):

| Файл | sha256 |
|---|---|
| `specs/catalog-m2c-selftest.md` | (эта спека) |
| `specs/checks/selftest_mutants_m2c.py` | `abd5175844cc2d2597e2408575cd322a14a3a5c62b8b923a051a3901b7c95a28` |

## Задача и почему

Веха 2a добавила `scripts/catalog_selftest.sh` (21 случай), вызываемый из `scripts/verify.sh`.
Мутационный прогон её приёмки (Codex, 10 новых мутантов поверх 27 старых) оставил 7
неэквивалентных выживших — поведение, которое самотест не проверяет вовсе:

| Мутант | Файл | Правка | Что пропускает CI |
|---|---|---|---|
| N01 | `scripts/build-mcpb.sh` | удалён блок `if ! printf … "$binary" \| grep -Eq '^[A-Za-z0-9_-]+$'` … `fi` | `binary: bad/name` доходит до Docker |
| N02 | `scripts/build-mcpb.sh` | в цикле `for name, opt in user_config.items():` пропуск всех, кроме `endpoint` | `pool` без `default` доходит до Docker |
| N04 | `scripts/provider_scaffold.sh` | `file_mode = modes[rel] if rel != "scripts/mcpb-checksums.sh" else None` | `--check` не видит потерю бита исполнения у `mcpb-checksums.sh` |
| N05 | `scripts/mcpb-checksums.sh` | `if [ -f "$sums" ]; then` → `if false; then` | строки архивов в `checksums.txt` теряются |
| N06 | `scripts/mcpb-checksums.sh` | `sha256sum -- "${names[@]}"` → `sha256sum -- /dev/null` | бандлы не хешируются (скрипт падает, CI молчит) |
| N08 | `templates/provider/release.yml` | `if [ "$version" != "$got" ] \|\| [ "$id" != "$want" ]; then` → `if false; then` | релиз с тегом, не равным версии `server.json`, проходит |
| N09 | `templates/provider/mcpb/manifest.json` | удалена строка `"description": "@@DESCRIPTION@@",` | манифест бандла без `description` |

Точные правки — в пробнике (функции `add("N01", …)` … `add("N09", …)`). Нужны семь новых
случаев самотеста, по одному на мутанта. Боевой код и шаблоны НЕ меняются: пробник
накладывает мутации по точным строкам и сверяет sha256 всех шести целей с BASE.

## Что проверено вживую, а что предположение

- Текущий `scripts/catalog_selftest.sh` на BASE: 21 случай, по строке `ok <case>` /
  `FAIL <case>: <причина>`, rc 0 тогда и только тогда, когда все `ok`. Хелперы в нём:
  `new_repo` (свежая копия фикстуры + `git init`), `capture` (cap_rc/cap_out/cap_err),
  `require_render`, `require_check_exact`, `jq_edit`, `build_env` (заглушка `docker` с
  маркером, `HOME` во временном каталоге), `require_build_blocked line|substr`. Порядок
  имён — массив `names=(…)` в конце, диспетчер — `run_named`.
- `build-mcpb.sh` (строки 25–30): `binary` берётся `sed -n 's/^binary: //p'` из
  `internal/provider/profile.yaml` и проверяется ДО Docker; отказ — stderr
  `build-mcpb: binary is not a safe token`, rc 1. Валидатор `user_config` (Python внутри
  скрипта) печатает имя поля без `default` отдельной строкой в stderr и выходит 1 — для
  `del(.user_config.pool.default)` это строка `pool`. Фикстура: `binary: selectel-s3`.
- `provider_scaffold.sh` рендерит `scripts/mcpb-checksums.sh` с режимом 0755 и в `--check`
  сверяет бит исполнения обоих скриптов (строки 116–120, 171–174); после `chmod 0644
  scripts/mcpb-checksums.sh` `--check` печатает строку `scripts/mcpb-checksums.sh`, rc 1.
- `mcpb-checksums.sh DIR SUMS`: имеющиеся строки SUMS, кроме строк `*.mcpb`, сохраняются
  байт-в-байт и в исходном порядке; затем дописываются `sha256sum` бандлов (имена
  отсортированы `LC_ALL=C`, формат — как у `cd DIR && sha256sum a.mcpb b.mcpb`); затем
  самопроверка `sha256sum -c`. Без SUMS файл создаётся. Скрипт можно звать прямо из kit
  (`bash "$kit/scripts/mcpb-checksums.sh"`), рендер для этого не нужен.
- Шаг `- name: Check the tag against server.json` в `templates/provider/release.yml`
  (строки 22–32): `run: |`, тело с отступом 10 пробелов, `set -euo pipefail`, читает
  `server.json` из текущего каталога через `jq`, тег из `GITHUB_REF_NAME`; при
  расхождении — stderr `tag … does not match server.json version …`, rc 1. На отрендеренном
  фикстурном провайдере тег `v0.1.0` проходит (`.version` = `0.1.0`), `v9.9.9` — отказ.
- `mcpb/manifest.json` после рендера содержит `.description`, равное `.description`
  `server.json` (рендерер подставляет `@@DESCRIPTION@@` из `server.json`); `static` пробника
  вехи 1 отсутствие поля не ловит (N09 выжил).
- Пробник `selftest_mutants_m2c.py` = пробник 2a + 7 мутантов + 7 новых имён случаев;
  проверен постановщиком на трёх зондах: эталонный самотест (28 случаев по таблицам 2a и
  ниже) — baseline зелёный, все 34 мутанта убиты своими случаями, ~2.5 мин, shellcheck чист;
  самотест, печатающий `ok` на все 28 имён, — 34 выживших, rc 1; самотест BASE (21 случай) —
  отказ baseline с перечнем семи недостающих случаев.
- Пробник требует, чтобы мутант в одном файле не валил случаи, не трогающие этот файл
  («побочные» префиксы по группам — см. словарь `prefix` в пробнике). Отсюда требование
  к новым случаям `checksums-*`: они зовут `mcpb-checksums.sh` kit напрямую, без рендера и
  без `build-mcpb.sh`.

## Что сделать

1. **`scripts/catalog_selftest.sh`** — добавить семь случаев (имена дословно, пробник ищет
   их; дописать в `run_named` и в конец массива `names`, после `static-exec-bit`, в этом
   порядке). Прежние 21 случай не менять по смыслу. Те же правила, что в 2a: свой временный
   каталог на случай, без Docker, без записи в настоящий `$HOME` и дерево kit, правки JSON —
   `jq`; каждый отрицательный случай проверяет И код возврата, И свою причину.

| Случай | Что делает и что требует |
|---|---|
| `check-exec-bit-checksums` | после рендера `chmod 0644 scripts/mcpb-checksums.sh`; `--check` rc≠0 и печатает ровно строку `scripts/mcpb-checksums.sh` (как `check-exec-bit`) |
| `render-description` | после рендера `.description` в `mcpb/manifest.json` существует, непусто и равно `.description` из `server.json` |
| `release-tag-mismatch` | после рендера извлечь тело `run: \|` шага `Check the tag against server.json` из `.github/workflows/release.yml` (снять 10 пробелов отступа) и выполнить его `bash -c` в каталоге провайдера: с `GITHUB_REF_NAME=v<.version из server.json>` rc 0 (положительный контроль: шаг найден и исполняем); с `GITHUB_REF_NAME=v9.9.9` rc≠0 и stderr содержит `does not match server.json`. Шаг не найден — `FAIL` |
| `build-unsafe-binary` | после рендера в `profile.yaml` строку `binary: …` заменить на `binary: bad/name`; `VERSION=0.0.1`; rc≠0, stderr содержит `binary is not a safe token`, `docker` не вызван |
| `build-missing-pool-default` | после рендера `del(.user_config.pool.default)` в `mcpb/manifest.json`; `VERSION=0.0.1`; rc≠0, в stderr строка, РАВНАЯ `pool`, `docker` не вызван, `*.mcpb` нет |
| `checksums-keep-archive` | без рендера: каталог с `bundles/a.mcpb` и `checksums.txt` из трёх строк — две строки архивов (`<64 hex>  <имя>.tar.gz`, НЕ в алфавитном порядке) и устаревшая строка `<64 hex>  a.mcpb`; `bash "$kit/scripts/mcpb-checksums.sh" bundles checksums.txt` rc 0; первые две строки результата байт-в-байт равны строкам архивов в исходном порядке, всего строк 3 |
| `checksums-bundle-hash` | без рендера: `bundles/` с двумя бандлами разного содержимого (`a.mcpb`, `b.mcpb`), `checksums.txt` нет; скрипт rc 0; файл байт-в-байт равен выводу `cd bundles && sha256sum a.mcpb b.mcpb` |

2. **`CHANGELOG.md`** — одна запись в раздел `## 2026-10-14` (или новый раздел с датой
   коммита): самотест ловит семь мутантов приёмки 2a.

`scripts/verify.sh` уже зовёт самотест — его не менять.

## Не трогать

- `scripts/provider_scaffold.sh`, `scripts/build-mcpb.sh`, `scripts/mcpb-checksums.sh`,
  `templates/**`, `specs/checks/**`, `testdata/**`, `scripts/verify.sh`, эту спеку, весь
  Go-код, `go.mod/go.sum`, `.github/**`, README, docs, skills.
  Нашёл дефект в боевом скрипте или шаблоне — НЕ чини, опиши в `report.json` (`note`) и в
  `report-blocked.md`, если он мешает критерию.
- Никаких тегов, релизов, `git push`, `gh release`, публикаций, `docker push`.
- Ожидаемые изменения от BASE_SHA, РОВНО: `scripts/catalog_selftest.sh`, `CHANGELOG.md`,
  `specs/catalog-m2c-selftest.md`, `specs/checks/selftest_mutants_m2c.py` (последние два —
  коммит постановщика, исполнитель их не меняет).

## Разрешения

Чтение всех репо, правка перечисленных файлов, Docker под своим uid (`-u "$(id -u):$(id -g)"`),
сеть для Go-модулей, локальные коммиты в клоне (≤50 символов, imperative, без подписей и
Co-Authored-By).

## Критерии приёмки

Команды запускаются из корня клона.

**AC-001 — Изменены только разрешённые пути, ветка catalog-m2c, дерево чистое.**
`bash -c 'set -e; B=9ab121722e3b93507aa9dc153bc391ffe1f8718c; test "$(git branch --show-current)" = catalog-m2c; git diff --check $B HEAD; git diff --quiet $B HEAD -- . ":(exclude)scripts/catalog_selftest.sh" ":(exclude)CHANGELOG.md" ":(exclude)specs/catalog-m2c-selftest.md" ":(exclude)specs/checks/selftest_mutants_m2c.py"; test -n "$(git diff --name-only $B HEAD -- CHANGELOG.md)"; test -n "$(git diff --name-only $B HEAD -- scripts/catalog_selftest.sh)"; test -z "$(git status --porcelain -- . ":(exclude)report.json" ":(exclude)report-blocked.md")"'`

**AC-002 — Shellcheck чист на самотесте.**
`bash -c 'docker run --rm -u "$(id -u):$(id -g)" -v "$PWD:/mnt:ro" -w /mnt koalaman/shellcheck:v0.11.0 scripts/catalog_selftest.sh'`

**AC-003 — Самотест зелёный, ровно 28 случаев ok, без Docker, без записи в HOME и в дерево.**
`bash -c 'set -e; d=$(mktemp -d); mkdir $d/bin $d/home; printf "#!/bin/sh\ntouch %s/real-docker-called\nexit 1\n" "$d" > $d/bin/docker; chmod +x $d/bin/docker; env HOME=$d/home PATH="$d/bin:$PATH" bash scripts/catalog_selftest.sh > $d/out; test "$(grep -c "^ok " $d/out)" = 28; test "$(wc -l < $d/out)" = 28; test -z "$(grep "^FAIL" $d/out)"; test ! -e $d/real-docker-called; test -z "$(ls -A $d/home)"; test -z "$(git status --porcelain -- . ":(exclude)report.json" ":(exclude)report-blocked.md")"'`

**AC-004 — Пробник постановщика: все 34 мутанта (27 вехи 1 и 7 приёмки 2a) убиты своими случаями.**
`bash -c 'set -e; echo "abd5175844cc2d2597e2408575cd322a14a3a5c62b8b923a051a3901b7c95a28  specs/checks/selftest_mutants_m2c.py" | sha256sum -c -; python3 -I specs/checks/selftest_mutants_m2c.py "$PWD"'`

**AC-005 — Полный verify kit зелёный.**
`bash -c 'set -e; grep -qxF "bash \"\$kit/scripts/catalog_selftest.sh\"" scripts/verify.sh; bash scripts/verify.sh'`

## Контракт отчёта

`report.json` в КОРНЕ клона, untracked, схема v2 (её проверяет `accept_run.py` до запуска
критериев):

```json
{"schema_version": 2,
 "policy_id": "cross-review-v1",
 "handoff_status": "ready",
 "executor": {"backend": "grok|spark|codex", "model": "<точная модель>"},
 "spec_sha256": "<sha256 файла specs/catalog-m2c-selftest.md>",
 "base_sha": "9ab121722e3b93507aa9dc153bc391ffe1f8718c",
 "reviewed_sha": "<коммит, отданный на ревью>",
 "final_sha": "<HEAD клона после единственного захода фиксов>",
 "review": {"initial_receipts": [], "verification_receipts": [], "resolutions": []},
 "criteria": [{"id": "AC-001", "status": "pass|fail|blocked",
               "command": "<команда ИЗ ЭТОЙ СПЕКИ, посимвольно>", "rc": 0, "note": "…"}]}
```

Записей в `criteria` ровно 5, по одной на критерий. Поле — `reviewed_sha`, не `review_sha`;
три sha — 40 строчных hex; `final_sha` = HEAD клона; `base_sha → reviewed_sha → final_sha` —
предки друг друга. `command` совпадает с командой критерия ДОСЛОВНО. Квитанции ревью
перечисляются в `review.initial_receipts` / `review.verification_receipts`. Перед сдачей:
`python3 /home/deploy/.claude/skills/executor-milestone/scripts/accept_run.py /home/deploy/exec-clones/s3kit-catalog-m2c --spec /home/deploy/exec-clones/s3kit-catalog-m2c/specs/catalog-m2c-selftest.md --dry-run`
обязан дать код 2 (`validation_only`).

`blocked` — штатный исход, когда среда не даёт выполнить критерий: `"rc": null`, в `command`
команда-улика, в `note` дословная ошибка. Обходить несовместимость (`--no-deps`, `|| true`,
`set +e` в команде критерия, `sudo`, `git push`) ЗАПРЕЩЕНО.

## Контракт на невыполнимое

Противоречие в спеке, невыполнимый критерий, факт, опровергающий раздел «Что проверено»
(сообщение скрипта не то, пробник падает на baseline при честном самотесте, мутант
невозможно убить без правки боевого скрипта или шаблона) — **остановись и доложи**:
`report-blocked.md` в корне клона с дословной командой, выводом и опровергнутым
утверждением. Править пробник, спеку, боевые скрипты и шаблоны, ослаблять критерии —
запрещено.

## Автономное перекрёстное ревью

Действует `cross-review-v1` целиком: `/home/deploy/.claude/skills/executor-milestone/docs/cross-review-v1.md`.
Пара ревьюеров по backend исполнителя: Codex или Spark → `agy` + `grok`; Grok → `codex` + `agy`.
Сам себя не ревьюит никто.

1. Реализация → своя проверка всех AC → коммит: это REVIEW_SHA.
2. Оба ревью параллельно на `BASE_SHA..REVIEW_SHA`, каждое только читает:
   `bash /home/deploy/.claude/skills/executor-milestone/scripts/review_run.sh initial <ревьюер> --clone /home/deploy/exec-clones/s3kit-catalog-m2c --base 9ab121722e3b93507aa9dc153bc391ffe1f8718c --range 9ab121722e3b93507aa9dc153bc391ffe1f8718c..<REVIEW_SHA> --context "S3 kit catalog self-test milestone 2c, read-only"`
   run_id = `s3kit-catalog-m2c-9ab121722e3b`; квитанции пишет только `review_run.sh`.
3. Дождаться ОБОИХ, свести находки, по каждой `fixed` / `disproved` / `needs_owner`.
   Один заход исправлений → FINAL_SHA. Затем те же два ревьюера ОДИН раз на
   `REVIEW_SHA..FINAL_SHA` (фаза `verification`, тот же `--base 9ab121722e3b93507aa9dc153bc391ffe1f8718c`);
   если код после ревью не менялся и споров нет — завершающая проверка пропускается. Второй
   заход исправлений запрещён.
4. Обрезанный вход, оборванный ответ или нет маркера `ВЕРДИКТ:` — `incomplete`, а не «находок
   нет». Один технический повтор незавершённого вызова допустим; исчерпанная квота —
   `blocked`. Эксперименты с процессами, сигналами и tmux — только в Docker с фейками.

## Стыки с соседними вехами

Вехи раскатки обвязки на провайдеров рендерят боевыми скриптами вехи 1, которые здесь не
меняются. Самотест обещает: любая будущая правка рендерера, сборщика, `mcpb-checksums.sh`,
шаблонов release/manifest или пробника, ломающая перечисленное поведение, краснеет в CI kit.
