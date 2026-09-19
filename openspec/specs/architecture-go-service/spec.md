# architecture-go-service Specification

## Purpose

Фиксирует структуру Go-микросервиса по слоям (transport → service → store), нейминг пакетов, файлов и типов, чтобы каждый сервис читался одинаково, а направление зависимостей проверял компилятор и тесты.

## Requirements

### Requirement: Дерево сервиса фиксировано
Каждый Go-сервис `<name>` SHALL иметь структуру:

```
cmd/<name>/
  main.go                 композиция: conf → store → service → transport → Start; только wiring, без логики
  etc/<name>.yaml         конфиг go-zero с ${ENV}
internal/<name>/
  config.go               package <name>: Config (go-zero conf) и производные Options
  transport/              package transport: вход. grpc.go — Server, реализует pb-интерфейс;
                          http.go + routes.go — только для REST-сервисов (auth). Маппинг pb/JSON ↔ типы service, коды ошибок
  service/                package service: use-cases. service.go — Service и его методы; errors.go — ошибки предметной области (var ErrX = errors.New);
                          интерфейсы внешних не-хранилищ (Mailer, TokenIssuer …) объявляет service, здесь же — их чистые помощники (password.go, token.go)
  store/                  package store: модели (GORM-структуры) + интерфейсы хранилищ в store.go; реализации по файлу на технологию:
                          gorm.go, redis.go, memory.go (in-memory — для тестов и dev)
  adapter/                package adapter (опционально): реализации интерфейсов service для внешних систем — smtp.go, <other>_grpc.go
tests/<name>/             package <name>_test: тесты снаружи пакета, по файлу на слой: service_test.go, transport_test.go, store_test.go
```

#### Scenario: Создание сервиса генератором
- **WHEN** выполняется `make new-service NAME=media`
- **THEN** создаются `cmd/media/{main.go,etc/media.yaml}`, `internal/media/config.go`, `internal/media/transport/grpc.go`, `internal/media/service/service.go`, `tests/media/service_test.go`, и `go vet ./... && go test ./...` проходят

#### Scenario: Логика в main.go
- **WHEN** в `cmd/<name>/main.go` появляется функция помимо `main` и чтения флагов/конфига, либо `main.go` импортирует `store` реализацию вместо конструктора
- **THEN** ревью возвращает change: `main.go` — только композиция

### Requirement: Направление зависимостей между слоями
Импорты MUST идти только вниз: `transport → service → store`; `adapter → store` (для типов) допустимо; `store` MUST NOT импортировать `service` и `transport`; `service` MUST NOT импортировать `transport`; `adapter` MUST NOT импортировать `transport`. Ни один пакет `internal/<a>/…` MUST NOT импортировать `internal/<b>/…` другого сервиса — общий код выносится в `internal/pkg/<name>` (без зависимостей на сервисы).

#### Scenario: Хранилище импортирует сервис
- **WHEN** `internal/auth/store/gorm.go` импортирует `internal/auth/service`
- **THEN** `go test ./tests/architecture/...` падает с указанием файла и запрещённого импорта, и `golangci-lint run` (depguard) сообщает то же

#### Scenario: Сервис A импортирует сервис B
- **WHEN** `internal/ping/service` импортирует `internal/auth/store`
- **THEN** архитектурный тест падает

### Requirement: Нейминг типов и файлов
Имена SHALL быть: пакет — имя слоя (`transport`, `service`, `store`, `adapter`), без префикса сервиса; входной тип — `transport.Server` (gRPC) или `transport.Handler` (REST); use-cases — `service.Service` с методами-глаголами (`Register`, `Login`); интерфейсы хранилищ — `store.<Entity>Store`; реализации — `store.Gorm<Entity>Store`, `store.Redis<Entity>Store`, `store.Memory<Entity>Store` с конструкторами `New<Impl><Entity>Store`; интерфейсы внешних систем — `service.<Role>` (`Mailer`), реализации — `adapter.SMTP<Role>`; ошибки — `service.Err<What>`. Файлы — snake_case, один файл на технологию/роль, без суффикса `_impl`.

#### Scenario: Реализация названа без технологии
- **WHEN** в `store/` появляется тип `UserStoreImpl`
- **THEN** ревью возвращает change: имя MUST быть `<Tech><Entity>Store`

### Requirement: Тесты снаружи пакета
Тесты SHALL лежать в `tests/<name>/` (`package <name>_test`) и работать через публичный API слоёв; `store.Memory*` используются как подмены хранилищ, интерфейсы `service` подменяются фейками, объявленными в тестовом файле. Внутри `internal/` тестов MUST NOT быть.

#### Scenario: Тест положен рядом с кодом
- **WHEN** появляется `internal/auth/service/service_test.go`
- **THEN** архитектурный тест падает: тесты — только в `tests/<name>/`
