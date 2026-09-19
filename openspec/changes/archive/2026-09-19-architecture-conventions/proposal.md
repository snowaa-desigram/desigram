## Why

Код в трёх языках (Symfony core, Go, Python) сейчас устроен по-разному, и правила «где что лежит и как называется» живут только в README и в головах: для core есть deptrac и тест изоляции контекстов, для Go и Python — ничего, кроме привычки. Пока сервисов два-три, это терпимо; перед ростом числа контекстов и микросервисов нужно зафиксировать по одной архитектуре на язык, проверять её автоматически и дать человеку способ *увидеть* связанность кода, а не вычитывать её из импортов.

## What Changes

- **Процесс проектирования**: перед реализацией любого change в `design.md` обязательна секция «Паттерны» — выбор из каталога GoF (или явное «без паттерна») с обоснованием, по скиллу `gof-design-patterns`. Правила зашиваются в `openspec/config.yaml`.
- **Symfony core**: фиксируется полное дерево контекста (`Domain/{Model,ValueObject,Event,Repository,Exception}`, `Application/{Command,Query,Port,EventSubscriber}`, `Infrastructure/{Grpc,Persistence/Doctrine}`, `Presentation/Http`) и нейминг классов; добавляется архитектурный тест нейминга рядом с `ContextIsolationTest`.
- **Go-сервисы** — **BREAKING** для внутренней структуры: плоский пакет `internal/<name>` разбивается на подпакеты по слоям `transport → service → store` (+ опциональный `adapter`); `auth` и `ping` рефакторятся, `scripts/new-service.sh` генерирует новую структуру; направление зависимостей проверяет тест `tests/architecture`.
- **Python-сервисы**: фиксируется структура `<name>_service/{server,settings,servicer,service,clients/}` и направление `servicer → service → clients`; `telegram` приводится к ней; проверка — `import-linter` в `make test`/CI.
- **archviz**: dev-only контейнер, `make archviz` генерирует графы зависимостей/вызовов (deptrac + phpmetrics для core, goda + go-callvis для Go, pydeps для Python) и отдаёт их одной страницей на `https://arch.<domain>`.
- README: разделы про архитектуру каждого языка ссылаются на спеки в `openspec/specs/`, добавляется раздел про `make archviz`.

## Capabilities

### New Capabilities
- `design-process`: что обязано быть спроектировано до кода — паттерны, слои, нейминг; как это проверяется на ревью.
- `architecture-core`: структура контекста, слои и нейминг Symfony core; что проверяют deptrac и архитектурные тесты.
- `architecture-go-service`: структура Go-микросервиса по слоям, нейминг пакетов/файлов/типов, направление зависимостей, где тесты.
- `architecture-python-service`: структура Python-микросервиса, слои, нейминг, направление импортов.
- `archviz`: страница с графами зависимостей и вызовов для локальной разработки; что на ней есть и как обновляется.

### Modified Capabilities
<!-- нет — специй в openspec/specs/ ещё не было -->

## Impact

- **backend** (сабмодуль): `services/go/internal/{auth,ping}` — перенос файлов по подпакетам, правки импортов в `cmd/*`, `tests/*`; новый `tests/architecture/layers_test.go`; `.golangci.yml` — depguard на слои. `services/python/telegram` — новые `service.py`, `clients/`; корневой `pyproject.toml` — `import-linter` в dev-группе и контракты. `core/tests/Architecture/NamingConventionTest.php`; `composer.json` — `phpmetrics/phpmetrics` в require-dev.
- **enviropment** (сабмодуль): `archviz/Dockerfile`, `archviz/render.sh`, `archviz/index.html`, сервис `archviz` в `docker-compose.dev.yml` (Traefik-роутер `arch.<domain>`), `.gitignore` для `var/archviz/`.
- **корень**: `openspec/config.yaml` (правила design/apply), `Makefile` (`archviz`, `arch.` в `DOMAINS`), `scripts/new-service.sh`, README, `.github/workflows` не меняются (проверки уже входят в `make test` / CI сабмодуля backend).
- Контракты (proto/OpenAPI) **не меняются**. Публичное поведение сервисов не меняется — только внутренняя структура и dev-инструменты.
