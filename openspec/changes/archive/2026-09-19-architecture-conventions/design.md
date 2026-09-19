## Context

Текущее состояние (см. proposal.md — Why):
- core: слои уже проверяет deptrac, изоляцию контекстов — `ContextIsolationTest`; нет проверки нейминга и папок внутри слоя.
- Go: `internal/auth` — один плоский пакет из 12 файлов (handler/service/store/mailer/token/…), `internal/ping` — два файла; `.golangci.yml` запрещает только `log` и rk-boot; тесты уже снаружи (`tests/<name>/`).
- Python: `telegram_service/servicer.py` совмещает транспорт и логику; проверок структуры нет.
- Скилл `gof-design-patterns` лежит в `.agents/skills/` (gitignored, ставится через `npx skills`); Claude Code его не подхватывает автоматически — нужен явный путь в правилах.
- Инструменты в CI/локально едины: `make test` (composer lint/test, go vet/test, ruff/pytest в контейнере uv). Образы собирает пользователь.

## Goals / Non-Goals

**Goals:**
- Одна структура на язык, проверяемая автоматически в `make test`/CI, а не только на ревью.
- Генератор `make new-service` и спеки описывают одно и то же дерево.
- Графы зависимостей строятся штатными инструментами каждого языка; страница — статическая.

**Non-Goals:**
- Не менять контракты, публичное API, compose-файлы прод-окружения.
- Не вводить hexagonal/clean architecture с отдельными `domain/`, `port/`, `usecase/` пакетами в Go/Python — сервисы тонкие, трёх слоёв достаточно.
- Не строить единый кросс-языковой граф (проверено: `emerge` не поддерживает PHP и заморожен на Python ≤3.10).

## Decisions

### D1. Go: три подпакета `transport / service / store` (+ `adapter`), модели и интерфейсы хранилищ — в `store`
Направление `transport → service → store`. Интерфейсы хранилищ объявляются рядом с моделями в `store/store.go`, а не в `service` — иначе цикл (service нужны модели из store, store реализует интерфейсы из service). Интерфейсы *не-хранилищ* (Mailer, TokenIssuer) объявляет потребитель — `service`; реализации с внешним I/O — в `adapter/` (SMTP). Чистые помощники без I/O (`password.go`, `token.go`) остаются в `service`.
Альтернативы: плоский пакет (отвергнут пользователем — нужны проверяемые слои); `domain/port/usecase/adapter` (избыточно для сервисов на 3–10 файлов).

### D2. Go: проверка слоёв — архитектурный тест на `go/parser` + depguard
`tests/architecture/layers_test.go` обходит `internal/*/`, парсит импорты (`parser.ImportsOnly`, без зависимостей) и проверяет: (а) матрицу разрешённых импортов между слоями, (б) отсутствие `internal/<a>` → `internal/<b>`, (в) отсутствие `_test.go` в `internal/`. Работает для любого нового сервиса без правок. depguard дублирует (а) для IDE-подсветки через `golangci-lint` (правила с `files:` глобами).
Альтернатива: `go-arch-lint`/`arch-go` — ещё один бинарник в CI и конфиг, который нужно поддерживать параллельно.

### D3. Python: `import-linter` с одним `layers`-контрактом на сервис
В корневом `pyproject.toml`: `[tool.importlinter]` с контрактами `layers` (`servicer → service → clients`) и `forbidden` (`service` не импортирует `grpc`, `*_pb2*`). Запуск `uv run lint-imports` добавляется в `make test` и CI backend рядом с ruff. Новый сервис — добавить контракт (5 строк), задача входит в чек-лист образца.
Альтернатива: `tach` — моложе, конфиг в TOML, но контракты грубее (модуль→модуль, без `forbidden` по внешним пакетам).

### D4. Core: `NamingConventionTest` в `tests/Architecture`
PHPUnit-тест обходит `src/<Context>/` и по пути файла проверяет: разрешённые подпапки слоёв, `Command/<Name>/{<Name>Command,<Name>Handler}`, `Query/<Name>/{Query,Handler,Result}`, суффиксы `Controller` в `Presentation/Http`, префикс технологии для классов в `Infrastructure/<Tech>/`, суффиксы `Gateway|Notifier|Client` в `Application/Port`. Один data-provider — по файлу на кейс, сообщение содержит ожидаемый путь.
Альтернатива: `phpat`/правила deptrac — deptrac видит только зависимости, не имена; phpat — ещё одна зависимость ради регулярок.

### D5. archviz: два compose-сервиса под профилем `archviz`, PHP-графы рендерит контейнер `core`
- `archviz-render` — образ `enviropment/archviz/Dockerfile`: `golang:1.25-bookworm` + `graphviz` + `uv`; в образе `goda` и `go-callvis` (`go install`), pydeps ставится через `uv run --with pydeps`. Монтирует `backend/` и `var/archviz/`, кеш модулей — named volume `go-mod-cache`. Команда — `render.sh`: обходит `cmd/*` и `members`, пишет SVG, лог ошибок в `<lang>/<name>.log`, собирает `index.html` из шаблона; падение одного генератора не останавливает остальные, итоговый код ненулевой.
- `archviz` — `nginx:alpine`, отдаёт `var/archviz/` на `arch.${DOMAIN}` через Traefik (labels как у mailpit).
- core: deptrac (`--formatter=graphviz-image`) и phpmetrics (`--report-html`) запускаются через `docker compose exec core` — там уже PHP и vendor; в dev-compose core получает volume `../var/archviz/core:/archviz`. phpmetrics — `require-dev` в `composer.json` (пользователь делает `composer update` при сборке).
Альтернатива: один «толстый» образ с PHP+Go+Python — дольше собирать, дублирует vendor.

### D6. Процесс проектирования — правила в `openspec/config.yaml`, скилл по пути
`rules.design` требует секцию «Паттерны» и размещение по слоям со ссылкой на спеки; `operations.apply.guidance` требует перечитать спеку архитектуры языка перед правкой. Скилл указывается путём `.agents/skills/gof-design-patterns/SKILL.md` + `resources/pattern-selection-guide.md`; в README — команда установки `npx skills add markpitt/claude-skills --skill gof-design-patterns`. Симлинк в `.claude/skills` не делаем: `.agents/` игнорируется git, симлинк у коллег будет битым.

## Паттерны

- **Ports & Adapters (GoF: Adapter)** — Go `service` объявляет интерфейсы внешних систем, `adapter/` и `store/` их реализуют; Python — `Protocol` в `service.py`, реализации в `clients/`. Альтернатива «интерфейс рядом с реализацией» отвергнута: тогда `service` зависит от `adapter`, и подмена в тестах требует импорта реализации.
- **Facade** — `desigram_common.serve()` и `cmd/<name>/main.go` как единственная точка сборки; новых фасадов не добавляем.
- **Без паттерна** — архитектурные тесты (Go/PHP): линейный обход файлов и таблица правил; Strategy/Chain для «набора правил» был бы избыточен при 5–7 проверках.

## Risks / Trade-offs

- [Рефакторинг auth затрагивает все файлы пакета, легко потерять поведение] → перенос через `git mv` без изменения тел функций, только пакеты/импорты/экспорт; существующие `tests/auth/*` — регрессия; `make e2e` после сборки пользователем.
- [go-callvis требует компиляции модуля в контейнере — медленно при холодном кеше и слабой сети] → named volume для `GOMODCACHE`; go-callvis помечен в `render.sh` как «опциональный» шаг: его падение не блокирует остальные графы.
- [phpmetrics может не поддерживать PHP 8.4 / Symfony-атрибуты] → если `composer require` не проходит, оставить только deptrac-граф и отметить в индексе; спека archviz требует отчёт, поэтому фиксируем как открытый вопрос.
- [import-linter замедляет `make test`] → пренебрежимо (секунды), контракты только на 3 модуля.
- [Правила config.yaml не заставят человека читать скилл] → секция «Паттерны» — формальный артефакт, её отсутствие видно на ревью и валидацией правил apply.

## Migration Plan

1. backend: добавить проверки (архитектурные тесты Go/PHP, import-linter) — они сразу красные для старой структуры.
2. backend: рефакторинг `ping` (2 файла), затем `auth`; обновить `cmd/*`, `tests/*`; `go vet && go test` зелёные.
3. backend: `telegram` → `service.py` + `clients/telegram_api.py`; `pytest` + `lint-imports` зелёные.
4. корень/enviropment: `new-service.sh`, archviz, Makefile, README, config.yaml.
5. Пользователь: пересобирает образы (`make dev`), гоняет `make test`, `make e2e`, `make archviz`.
Откат: сабмодули — по коммиту каждый; контракты не менялись, данные не трогались.

## Open Questions

- Совместимость `phpmetrics/phpmetrics` с PHP 8.4 проверится при `composer require` пользователем; при провале — только deptrac-граф для core, индекс это отражает.
