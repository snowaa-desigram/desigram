# Desigram

```bash
git clone --recurse-submodules git@github.com:snowaa-desigram/desigram.git
```

## Архитектура

```mermaid
flowchart LR
    U((Клиент)) -->|HTTPS| T[Traefik<br/>TLS · LB · rate-limit]
    T -->|desigram.*| F[Next.js]
    T -->|api.desigram.*| C[Symfony core · DDD<br/>реплики ×N]
    C -->|gRPC| P[Go: ping<br/>×N]
    C -->|gRPC| TG[Python: telegram<br/>×N]
    C -->|cache-aside| R[(Redis)]
    R -.->|miss| DB[(MySQL)]
    C -->|Messenger async| Q[(RabbitMQ)]
    Q --> W[core-worker<br/>×N]
    W -->|gRPC| TG
    W -->|gRPC| P
    W --> R
```

- **Traefik** — единственная точка входа. TLS (локально mkcert, в проде Let's Encrypt), балансировка между репликами, rate-limit на API, healthcheck.
- **Symfony core** (`backend/core`) — единственный публичный API и «оркестратор». DDD: `src/<Context>/{Domain,Application,Infrastructure,Presentation}` + `src/Shared`. Stateless (без сессий, кеш в Redis) → масштабируется репликами.
- **Redis** — только кеш. **В SQL ходим только через Redis**: Doctrine query/result/second-level cache живут в Redis во всех окружениях, репозитории наследуют `Shared/Infrastructure/Persistence/Doctrine/CachedRepository` (`remember()` — чтение через кеш, `save()/forget()` — запись + инвалидация, `cachedQuery()` — выборки с result cache). MySQL видит только промахи кеша и записи.
- **RabbitMQ** — очередь. Тяжёлые команды (например `SendPhotoCommand`) уходят в `async`-транспорт Messenger (AMQP), HTTP отвечает `202`, выполняет `core-worker`; retry ×3, упавшие — в `failed`.
- **Микросервисы** (`backend/services/*`) — внутренние, наружу не торчат, только gRPC.
  - Go: один модуль, бинарник на сервис (`cmd/<name>/main.go` + `etc/<name>.yaml`, `internal/<name>/{config,server}.go`). Каркас — [go-zero](https://go-zero.dev) `zrpc`: конфиг из YAML с `${ENV}`, логирование, health, Prometheus (`:9091/metrics`), OpenTelemetry-трейсы (в dev — в Jaeger), graceful shutdown; в `Mode: dev|test` включён gRPC reflection.
  - Python: uv-workspace `services/python/` — общий пакет `desigram-common` (`serve()`: health, reflection, логи, graceful shutdown, `Settings` из env) + сервисы (`telegram`).
- **Контракты** (`backend/proto`) — единственный источник правды для всех языков; код генерируется `buf` локальными плагинами (образ `enviropment/buf`, без зависимости от buf.build).
- **Frontend** (Next.js) — отдельный контейнер за Traefik. Из браузера ходит на `api.<domain>` (CORS в core через `nelmio/cors-bundle`, origin = `https://<domain>`), из SSR — напрямую в `http://core:8080` (`API_URL_INTERNAL`).

### Поток запроса (пример `GET /api/ping`)

```
Presentation (PingController)
  → QueryBus (Messenger, query.bus)
    → Application (PingHandler) → порт PingGateway (интерфейс)
      → Infrastructure (GrpcPingGateway) → gRPC → Go ping
```

Слои проверяет `deptrac` (`Domain ← Application ← Infrastructure/Presentation`), типы — `phpstan` (level 8), стиль — `php-cs-fixer`.

## Структура

```
backend/                 # git submodule
  proto/                 # gRPC-контракты (buf)
  core/                  # Symfony 7.4 LTS, PHP 8.4, FrankenPHP
  services/go/           # Go gRPC-сервисы (go-zero): cmd/<name>/{main.go,etc/<name>.yaml}, internal/<name>, gen/
  services/python/       # uv-workspace: common/ (каркас + gen/), telegram/
enviropment/             # git submodule
  docker-compose.yml     # база + include: services/*.yml
  docker-compose.dev.yml # dev: volume, xdebug, порты, grafana/prometheus/jaeger
  docker-compose.prod.yml# prod: Let's Encrypt
  services/<name>.yml    # по файлу на микросервис
  ansible/               # ЕДИНАЯ ТОЧКА НАСТРОЙКИ + деплой
  php/ go/ python/ nextjs/ buf/  # Dockerfile'ы (buf — тулчейн генерации)
frontend/                # git submodule (Next.js)
scripts/new-service.sh   # генератор микросервиса
scripts/e2e.sh           # сквозная проверка поднятого стека
tests/load/api.js        # k6-сценарий «200 онлайн»
.github/workflows/       # e2e.yml (стек из сабмодулей), load.yml (k6)
```

## Единая точка настройки

Все параметры (домен, порты, креды MySQL/RabbitMQ, токены, число реплик, rate-limit, режим Go-сервисов) — в
`enviropment/ansible/inventory/group_vars/{all,local,prod}.yml`. Секреты — `ansible-vault`
(`vault.yml.example`). Из них Ansible генерирует `enviropment/.env`, который читает compose.

```bash
make configure          # group_vars -> enviropment/.env (локально)
make deploy             # prod-серверы из inventory: docker + git clone + compose up
```

## Локально

HTTPS на порту **8443** (80/443 заняты другим Docker).

```bash
make cert DOMAINS="desigram.localhost api.desigram.localhost traefik.desigram.localhost grafana.desigram.localhost prometheus.desigram.localhost jaeger.desigram.localhost rabbitmq.desigram.localhost"
make dev                # = make configure + compose up --build
```

Первая сборка `core` долгая: расширения `grpc`/`protobuf` компилируются из исходников (20+ мин; `amqp`, `redis` и прочие — быстро), дальше — из кеша. Если pecl отвалился по сети — просто повторить `make dev`.

| Что        | Где                                          |
| ---------- | -------------------------------------------- |
| Сайт       | https://desigram.localhost:8443              |
| API        | https://api.desigram.localhost:8443/api/ping |
| Профайлер  | https://api.desigram.localhost:8443/_profiler |
| Traefik    | https://traefik.desigram.localhost:8443/dashboard/ |
| Grafana    | https://grafana.desigram.localhost:8443 (admin/admin) |
| Prometheus | https://prometheus.desigram.localhost:8443   |
| Jaeger     | https://jaeger.desigram.localhost:8443       |
| RabbitMQ   | https://rabbitmq.desigram.localhost:8443 (desigram/desigram), AMQP 127.0.0.1:5673 |
| MySQL      | 127.0.0.1:3307                               |
| Redis      | 127.0.0.1:6380                               |
| gRPC ping / telegram | 127.0.0.1:50051 / 50052            |

```bash
make logs S=core        # логи
make core-console C="debug:router"
make core-lint          # cs-fixer + phpstan + deptrac
make core-test
XDEBUG_MODE=debug make dev   # xdebug -> IDE на 9003
```

Отладка в core: web-profiler (`/_profiler`), debug-bundle (`dump()`), monolog, xdebug, maker-bundle (`bin/console make:*`).

## Контракты gRPC

```bash
make proto              # генерация Go / PHP / Python из backend/proto
make proto-lint         # buf lint
make proto-breaking     # что сломалось относительно main (AGAINST=<ref>)
```

Проверить сервис вручную (reflection включён):

```bash
docker run --rm --network desigram fullstorydev/grpcurl -plaintext ping:50051 list
docker run --rm --network desigram fullstorydev/grpcurl -plaintext -d '{"message":"hi"}' ping:50051 desigram.ping.v1.PingService/Ping
```

## Новый микросервис

```bash
make new-service NAME=media
```

Создаёт proto-контракт, Go-код (`cmd/media/{main.go,etc/media.yaml}`, `internal/media/{config,server}.go`), `enviropment/services/media.yml`,
подключает его в compose и Prometheus, добавляет `MEDIA_GRPC_ADDR` и `MEDIA_REPLICAS` в настройки, генерирует код.
Остаётся описать RPC в proto и написать порт + gRPC-адаптер в core (пример — контекст `Ping`).

Python-сервис: скопировать `services/python/telegram/`, добавить в `members` корневого `pyproject.toml`,
`uv lock`, создать `enviropment/services/<name>.yml` по образцу `telegram.yml` (`args.SERVICE: <name>`).

## Тесты и CI

«Сломает ли мой код что-нибудь» отвечают слои, каждый ловит свой класс поломок. Всё гоняется на PR в GitHub Actions и локально теми же командами.

| Слой | Ловит | Где | Локально |
| --- | --- | --- | --- |
| Контракты | несовместимое изменение proto | `backend` ci → `proto` (buf lint/format/breaking против `main`) | `make proto-lint`, `make proto-breaking` |
| Архитектура | нарушение слоёв DDD, запрещённые импорты | deptrac (PHP), depguard в golangci-lint (Go) | `make core-lint`, `golangci-lint run` |
| Статика | типы, стиль | phpstan 8 + cs-fixer, `go vet` + golangci-lint, ruff | `make test` |
| Unit / интеграция | логика хендлеров; HTTP → шина → хендлер с in-memory портами (gRPC подменён, кеш — array) | `backend` ci → `php`/`go`/`python` | `make test` |
| Окружение | compose dev/prod, Dockerfile'ы (hadolint), Ansible (syntax + lint + рендер `.env`) | `enviropment` ci | `docker compose config` |
| E2E | HTTP → core → gRPC → Go/Python → RabbitMQ → worker | корень, `e2e.yml` (push в `main`, вручную) | `make dev && make e2e` |
| Нагрузка | p95/p99, доля ошибок при 200 VU; пороги в скрипте — вышли за них = красный job | корень, `load.yml` (кнопка / cron) | `make load TARGET=…` |

Тестовые подмены внешних сервисов — `core/tests/Fake/*`, подключаются в `when@test` в `config/services.yaml`: новый порт → новый фейк там же.

E2E в CI собирает образы через `docker buildx bake` с GHA-кешем: первый прогон долгий (grpc-расширение), дальше минуты. Для приватных сабмодулей нужен secret `SUBMODULES_TOKEN` (PAT с `repo`). k6 умеет слать метрики в Prometheus стека metrika — secret `K6_PROMETHEUS_RW_SERVER_URL`.

## Нагрузка

Что уже заложено и как крутить при росте:

| Уровень        | Что сделано                                                     | Ручка                                  |
| -------------- | --------------------------------------------------------------- | -------------------------------------- |
| Вход           | Traefik rate-limit per-IP, healthcheck, LB по репликам          | `core_rate_limit`, `core_rate_burst`   |
| API            | core stateless (без сессий, кеш в Redis)                        | `core_replicas`                        |
| БД             | SQL только через Redis: Doctrine L2/result cache + `CachedRepository`; MySQL видит промахи и записи | TTL в `doctrine.yaml` / `CachedRepository::TTL` |
| Тяжёлые задачи | Messenger async → RabbitMQ → `core-worker`, retry, failed-транспорт | `core_worker_replicas`                 |
| Микросервисы   | независимые реплики, gRPC-балансировка через DNS docker         | `service_replicas.<name>`              |
| Наблюдаемость  | Prometheus + Grafana + Jaeger (dev)                             | —                                      |

Следующие ступени, когда один сервер перестанет хватать: вынести MySQL/Redis/RabbitMQ на отдельные машины
(в `.env` это просто другие хосты), и перейти с compose на Swarm/K8s — контракты, образы и
структура сервисов при этом не меняются.
