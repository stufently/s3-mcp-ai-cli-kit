# Статус

- Завершено: публичный MIT-модуль, общие MCP/CLI/safety/s3core/installer/skill/conformance и переиспользуемый CI.
- Опубликован неизменённый v0.1.0 (`b8970d4`); Selectel, Yandex, VK Cloud, Cloud.ru Evolution, Timeweb Cloud и MWS Cloud Platform используют этот модуль.
- Опубликован patch v0.1.1 (`8259b84`) для Beget: независимые bucket_create/bucket_delete/bucket_config, прежние профили совместимы. Обе версии проверены загрузкой через Go-реестр.
- Проверки v0.1.0 завершены в Docker: build/vet/race/lint, versitygw, MCP smoke, 87/87 мутаций, signal/hash self-tests, actionlint.
- Проверки v0.1.1 завершены в Docker: тот же набор, 95/95 мутаций (100%); 32768 сочетаний capabilities/уровней/FILE_ROOT.
- CI опубликованного patch: [main](https://github.com/stufently/s3-mcp-ai-cli-kit/actions/runs/38066998833), [tag](https://github.com/stufently/s3-mcp-ai-cli-kit/actions/runs/38067000657). Статус текущей ветки — в [Actions](https://github.com/stufently/s3-mcp-ai-cli-kit/actions).
- Завершено: шесть провайдеров опубликованы строго по очереди; их профиль, ресерч, Docker-проверки, доставка и ограничения — в TASKS.md соответствующего репозитория.
- Завершено: публичное дерево Selectel очищено обычным коммитом; история сохранена.

## Нужна живая проверка

Каждое облако требует ключ владельца и тестового бакета. Эмулятор подтверждает реализацию, но не фактическую поддержку условий, API, presign, классов/цен и ошибок лимитов. Теги v0.1.0 провайдеров, OCI и MCP Registry остаются отложенными до живой проверки. Неподтверждённые сведения помечены **[предположение]** в ресерче провайдеров.

## Обнаружение семейства — 11.10.2026

- Завершено: каталог семи провайдеров в README RU/EN; взаимные ссылки и отдельные сценарии провайдеров.
- GitHub metadata всех восьми репозиториев проверены: двуязычные описания, 20 релевантных topics, homepage на общий каталог; чужие selectel-s3 topics заменены.
- GitHub Pages RU/EN опубликован: [каталог](https://stufently.github.io/s3-mcp-ai-cli-kit/) и [English](https://stufently.github.io/s3-mcp-ai-cli-kit/en/). Источник — main:/docs, HTTPS включён; HTTP 200, canonical/hreflang/JSON-LD, sitemap и OG PNG проверены на опубликованном сайте. Chromium — шесть сочетаний языка и viewport.
- Social preview: установлен во всех восьми репозиториях; `usesCustomOpenGraphImage=true` подтверждён через GitHub API 11.10.2026. SVG и PNG сохранены в `docs/assets/`. [Инструкция и PNG](docs/social-preview.md).
- Проверено 11.10.2026: установка из свежего публичного clone в Docker с пустыми HOME/Go-кэшем; конфиги Cursor, Claude Desktop, Codex, Claude Code project/user, skill и MCP smoke на всех восьми сочетаниях уровней доступа. В конфиги клиентов ключи не попадают; write/delete/admin по умолчанию выключены.
- Проверено в Docker: ссылки README и страниц, восемь PNG/SVG; у провайдеров check_docs (заголовки, compat и Registry schema). Доставлено в main 11.10.2026; текущие облачные CI-проверки — в [Actions](https://github.com/stufently/s3-mcp-ai-cli-kit/actions).

## Индексация и проверка ссылок — 11.10.2026

- Google Search Console: каталог подтверждён метатегом, доступ siteOwner; sitemap отправлен. Последняя проверка: Pending, RU/EN пока URL is unknown to Google. Это ожидание обхода, а не подтверждение включения в поиск.
- Яндекс.Вебмастер: MCP, прямой HTTPS-запрос и браузер возвращают connection timeout к api.webmaster.yandex.net; браузерная сессия Вебмастера отсутствует. Sitemap через этот кабинет не отправлен.
- IndexNow: файл подтверждения опубликован и проверен через MCP; область — только /s3-mcp-ai-cli-kit/. Оба URL RU/EN отправлены через MCP IndexNow, HTTP 202 Accepted (проверка нового ключа ожидается). Включение в поиск ещё не подтверждено. [Протокол Яндекса](https://yandex.ru/support/webmaster/ru/indexnow/reference), [обмен URL между участниками](https://www.indexnow.org/documentation).
- Telegram: восемь ссылок доставлены с включёнными крупными превью. GitHub отдаёт правильные PNG (HTTP 200 и побайтное совпадение); визуальная обрезка внутри Telegram не проверена, поскольку клиент без авторизации.
- Живые облачные проверки отложены до отдельного прогона. Релизы провайдеров, OCI и MCP Registry по-прежнему ждут их результатов.
