## 1. Правила процесса (корень)

- [x] 1.1 Обновить `openspec/config.yaml`: `rules.design` — обязательная секция «Паттерны» (по `.agents/skills/gof-design-patterns/…`) и размещение по слоям со ссылкой на спеки `architecture-*`; `operations.apply.guidance` — перечитать спеку архитектуры языка перед правкой; проверить `openspec doctor` без предупреждений
- [x] 1.2 README: раздел «Архитектура кода» со ссылками на `openspec/specs/architecture-*` и команду установки скилла `npx skills add markpitt/claude-skills --skill gof-design-patterns`; проверить, что ссылки на файлы существуют

## 2. Go: проверки и рефакторинг (backend/services/go)

- [x] 2.1 Добавить `tests/architecture/layers_test.go` (go/parser, ImportsOnly): матрица слоёв, запрет `internal/<a>`→`internal/<b>`, запрет `_test.go` в `internal/`; проверить, что тест **падает** на текущей плоской структуре с понятным сообщением
- [x] 2.2 Добавить в `.golangci.yml` depguard-правила по `files:` глобам (`**/store/**` не импортирует `service|transport`, `**/service/**` не импортирует `transport`); проверить `golangci-lint config verify`
- [x] 2.3 Рефакторинг `ping`: `internal/ping/transport/grpc.go` (Server), `config.go` остаётся; обновить `cmd/ping/main.go`, `tests/ping/`; `go vet ./... && go test ./tests/ping/... ./tests/architecture/...` зелёные
- [x] 2.4 Рефакторинг `auth` через `git mv`: `store/{store,gorm,redis,memory}.go`, `service/{service,errors,password,token}.go`, `adapter/smtp.go` (Mailer из `service`), `transport/{http,routes,errors}.go`; `metrics.go` — в `service` (метрики операций Service, не HTTP); переименовать `GormUserStore`→`store.GormUserStore` и т.п. по спеке; обновить `cmd/auth/main.go`, `tests/auth/*`; `go vet ./... && go test ./...` зелёные, `golangci-lint run` чистый
- [x] 2.5 Обновить `scripts/new-service.sh` под новую структуру (transport/grpc.go, service/service.go, tests/<name>/service_test.go); проверить генерацией `NAME=tmpsvc` в scratch-копии, что `go vet ./... && go test ./...` проходят, затем удалить

## 3. Python: проверки и рефакторинг (backend/services/python)

- [x] 3.1 В корневом `pyproject.toml`: `import-linter` в `dev`, `[tool.importlinter]` с контрактами `layers` и `forbidden` для `telegram_service`; `uv lock`; проверить, что `uv run lint-imports` **падает** на текущем `servicer.py` (импортирует grpc и содержит логику — после 3.2 зелёный)
- [x] 3.2 Рефакторинг `telegram`: `service.py` (`TelegramService`, `Protocol PhotoSender`), `clients/telegram_api.py` (`TelegramApiPhotoSender`, пока заглушка с логом), `settings.py`, `servicer.py` — только маппинг; `server.py` — wiring; тесты `test_service.py` (FakePhotoSender) и `test_servicer.py`; `ruff check`, `lint-imports`, `pytest` зелёные
- [x] 3.3 Добавить `lint-imports` в `make test` (корневой Makefile) и в CI backend (`backend/.github/workflows/*` job python) рядом с ruff; проверить локальной командой из Makefile

## 4. Core: проверка нейминга (backend/core)

- [x] 4.1 Добавить `tests/Architecture/NamingConventionTest.php` (обход `src/<Context>/`, правила из спеки `architecture-core`, сообщение с ожидаемым путём); проверить на текущем `src` — зелёный, и на временно неверно названном файле — красный
- [x] 4.2 Добавить `phpmetrics/phpmetrics` в `require-dev` `composer.json` (поставлен локально через composer, lock обновлён; v2.11 работает на PHP 8.5)

## 5. archviz (enviropment + корень)

- [x] 5.1 `enviropment/archviz/Dockerfile` (golang:1.25-bookworm + graphviz + uv + goda + go-callvis), `hadolint` чистый
- [x] 5.2 `enviropment/archviz/render.sh`: обход `cmd/*` (goda + go-callvis, `-nostd`, без `gen/`), `members` из `pyproject.toml` (pydeps через `uv run --with pydeps`), логи ошибок, ненулевой код при любом падении; `index.html` генерируется в `render.sh` (шаблон не нужен) со ссылками и пометками «не собран»; `shellcheck` чистый
- [x] 5.3 `docker-compose.dev.yml`: сервисы `archviz-render` и `archviz` (nginx, Traefik `arch.${DOMAIN}`, `profiles: [archviz]`), volume `../var/archviz/core:/archviz` у `core`, named volume `go-mod-cache`; проверить `docker compose -f docker-compose.yml -f docker-compose.dev.yml config` и что в prod-`config` сервиса нет
- [x] 5.4 Makefile: цель `archviz` (deptrac graphviz + phpmetrics через `exec core`, `run --rm archviz-render`, `up -d archviz`), `arch` в `DOMAINS`; `.gitignore` корня — `var/`; `make -n archviz` показывает ожидаемые команды
- [x] 5.5 README: раздел «Граф кода (archviz)» — что генерируется, где смотреть, что нужно (`make cert` для `arch.<domain>`)

## 6. Проверка пользователем (после сборки образов)

- [x] 6.1 `make dev && make test` — все слои зелёные, включая новые архитектурные тесты и `lint-imports`
- [x] 6.2 `make e2e` — auth-сценарий проходит после рефакторинга
- [x] 6.3 `make archviz` — `https://arch.<domain>` показывает индекс, все графы собраны (или помечены с логом)
