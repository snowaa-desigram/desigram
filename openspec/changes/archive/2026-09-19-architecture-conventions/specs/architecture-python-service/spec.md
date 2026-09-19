## Purpose

Фиксирует структуру Python-микросервиса (servicer → service → clients), нейминг модулей и классов, чтобы Python-сервисы читались так же предсказуемо, как Go и core.

## ADDED Requirements

### Requirement: Дерево сервиса фиксировано
Каждый Python-сервис `<name>` в uv-workspace SHALL иметь структуру:

```
services/python/<name>/
  pyproject.toml            member workspace, script `<name>-service = "<name>_service.server:main"`
  <name>_service/
    __init__.py
    server.py               точка входа main(): Settings → clients → Service → Servicer → desigram_common.serve(); только wiring
    settings.py             class Settings(desigram_common.Settings) — свои переменные окружения (если есть)
    servicer.py             transport: class <Name>Servicer(<pb>_grpc.<Name>ServiceServicer) — маппинг pb ↔ python, grpc-статусы, вызов Service
    service.py              use-cases: class <Name>Service — чистый Python, без grpc и pb; объявляет Protocol-интерфейсы нужных клиентов
    clients/                адаптеры внешних систем: <system>.py (telegram_api.py) — реализуют Protocol из service.py
  tests/
    test_service.py         Service с фейковыми клиентами
    test_servicer.py        Servicer с фейковым Service
```

#### Scenario: Новый сервис по образцу
- **WHEN** сервис создан копированием `telegram/` и добавлен в `members` корневого `pyproject.toml`
- **THEN** в нём есть `server.py`, `servicer.py`, `service.py`, `clients/`, `tests/`; `uv run ruff check .`, `uv run lint-imports`, `uv run pytest` проходят

### Requirement: Направление импортов
Импорты MUST идти только вниз: `servicer → service → clients`; `server` может импортировать все; `service` MUST NOT импортировать `grpc`, `*_pb2`, `*_pb2_grpc` и `servicer`; `clients` MUST NOT импортировать `service` (кроме `typing`-контрактов через `Protocol`, объявленных в `service.py` — допускается импорт только типов под `TYPE_CHECKING`) и `servicer`. Сервис MUST NOT импортировать пакет другого сервиса — общее в `desigram_common`.

#### Scenario: Бизнес-логика тянет grpc
- **WHEN** `telegram_service/service.py` импортирует `grpc` или `telegram_pb2`
- **THEN** `uv run lint-imports` падает с именем контракта и цепочкой импортов, `make test` красный

#### Scenario: Клиент импортирует servicer
- **WHEN** `clients/telegram_api.py` импортирует `telegram_service.servicer`
- **THEN** `lint-imports` падает

### Requirement: Нейминг
Имена SHALL быть: пакет — `<name>_service`; `Servicer` — `<Name>Servicer`; use-cases — `<Name>Service` с методами-глаголами в snake_case; интерфейсы клиентов — `Protocol` с именем роли (`PhotoSender`); реализации — `<System><Role>` (`TelegramApiPhotoSender`) в `clients/<system>.py`; фейки в тестах — `Fake<Role>`; ошибки — `<What>Error(Exception)` в `service.py`.

#### Scenario: Реализация клиента внутри service.py
- **WHEN** в `service.py` появляется класс, делающий HTTP-вызов
- **THEN** ревью возвращает change: вызовы внешних систем — только в `clients/`
