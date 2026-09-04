# Desigram

Локально всё на HTTPS, порт **8443** (80 и 443 заняты другим Docker).

```bash
make cert DOMAINS="desigram.localhost traefik.desigram.localhost grafana.desigram.localhost prometheus.desigram.localhost jaeger.desigram.localhost"
make dev
```

`make stop` — остановить, `make down` — убрать контейнеры.

## Ссылки

| Название | Ссылка | Зачем |
|---|---|---|
| Echo (Go) | https://desigram.localhost:8443 | Тестовый сервер: повторяет запрос. `/health` — жив ли процесс |
| Traefik | https://traefik.desigram.localhost:8443/dashboard/ | Входной прокси: кто куда идёт, HTTPS, список сервисов |
| Grafana | https://grafana.desigram.localhost:8443 | Графики. Логин `admin` / `admin` |
| Prometheus | https://prometheus.desigram.localhost:8443 | Счётчики запросов, статусы целей |
| Jaeger | https://jaeger.desigram.localhost:8443 | Трассы: как запрос прошёл через Traefik |

MySQL с Mac: `127.0.0.1:3307`. Пользователь и пароль в `enviropment/.env`.
