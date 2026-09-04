# Desigram

```bash
git clone --recurse-submodules git@github.com:snowaa-desigram/desigram.git
```

Локально всё на HTTPS, порт **8443** (80 и 443 заняты другим Docker).

```bash
make cert DOMAINS="desigram.localhost api.desigram.localhost traefik.desigram.localhost grafana.desigram.localhost prometheus.desigram.localhost jaeger.desigram.localhost"
make dev
```

`make stop` — остановить, `make down` — убрать контейнеры.

## Ссылки


| Название   | Ссылка                                                                                                   | Зачем                                                         |
| ---------- | -------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------- |
| Next.js    | [https://desigram.localhost:8443](https://desigram.localhost:8443)                                       | Сайт. В проде — `https://desigram.com`                        |
| Echo (Go)  | [https://api.desigram.localhost:8443](https://api.desigram.localhost:8443)                               | API. `/health` — жив ли процесс. В проде — `api.desigram.com` |
| Traefik    | [https://traefik.desigram.localhost:8443/dashboard/](https://traefik.desigram.localhost:8443/dashboard/) | Входной прокси: кто куда идёт, HTTPS, список сервисов         |
| Grafana    | [https://grafana.desigram.localhost:8443](https://grafana.desigram.localhost:8443)                       | Графики. Логин `admin` / `admin`                              |
| Prometheus | [https://prometheus.desigram.localhost:8443](https://prometheus.desigram.localhost:8443)                 | Счётчики запросов, статусы целей                              |
| Jaeger     | [https://jaeger.desigram.localhost:8443](https://jaeger.desigram.localhost:8443)                         | Трассы: как запрос прошёл через Traefik                       |


MySQL с Mac: `127.0.0.1:3307`. Пользователь и пароль в `enviropment/.env`.