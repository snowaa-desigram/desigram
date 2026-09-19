## Purpose

Даёт разработчику страницу с графами зависимостей и вызовов всего проекта в локальном окружении, чтобы связанность кода можно было увидеть, а не восстанавливать по импортам.

## ADDED Requirements

### Requirement: Одна команда собирает все графы
`make archviz` SHALL сгенерировать в `var/archviz/` (в корне монорепо, игнорируется git) и открыть на `https://arch.<domain>` страницу-индекс со ссылками на:
- core: граф слоёв и контекстов (deptrac), отчёт по классам с графом зависимостей и метриками связанности (phpmetrics);
- Go: граф пакетов всего модуля (`goda`) и граф вызовов по каждому сервису `cmd/<name>` (`go-callvis`), без stdlib и `gen/`;
- Python: граф модулей по каждому сервису (`pydeps`), без `gen/` и stdlib.
Все результаты — статические SVG/HTML, открываются без JS-зависимостей из сети.

#### Scenario: Первый запуск
- **WHEN** стек поднят (`make dev`) и выполняется `make archviz`
- **THEN** в `var/archviz/` появляются `index.html`, `core/layers.svg`, `core/metrics/index.html`, `go/packages.svg`, `go/<name>.svg` для каждого `cmd/<name>`, `python/<name>.svg` для каждого member; `https://arch.<domain>` отдаёт индекс со всеми ссылками рабочими

#### Scenario: Один из генераторов упал
- **WHEN** например `go-callvis` не смог собрать один сервис
- **THEN** остальные графы всё равно генерируются, индекс помечает отсутствующий граф как «не собран» с текстом ошибки в `var/archviz/<lang>/<name>.log`, команда завершается ненулевым кодом

### Requirement: Только dev-окружение
Сервис `archviz` SHALL объявляться только в `docker-compose.dev.yml`, не входить в `docker-compose.yml`/`prod` и не запускаться при `make dev` (profile), а подниматься только по `make archviz`; хост `arch.<domain>` MUST входить в `DOMAINS` для `make cert`.

#### Scenario: Прод-конфиг
- **WHEN** выполняется `docker compose -f docker-compose.yml -f docker-compose.prod.yml config`
- **THEN** сервиса `archviz` в выводе нет

### Requirement: Новый сервис попадает в графы без правок
Генерация SHALL обнаруживать сервисы автоматически: Go — по `cmd/*`, Python — по `members` корневого `pyproject.toml`, core — по `src/*`.

#### Scenario: После make new-service
- **WHEN** добавлен сервис `media` и выполнен `make archviz`
- **THEN** на индексе появляется `go/media.svg` без изменений в скриптах archviz
