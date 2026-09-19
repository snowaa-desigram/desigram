COMPOSE = docker compose -f enviropment/docker-compose.yml
DEV     = $(COMPOSE) -f enviropment/docker-compose.dev.yml
PROD    = $(COMPOSE) -f enviropment/docker-compose.prod.yml
# Домен/имя проекта — из enviropment/.env (генерируется make configure из group_vars); до configure — дефолты
ENV_FILE = enviropment/.env
env      = $(or $(shell test -f $(ENV_FILE) && sed -n 's/^$(1)=//p' $(ENV_FILE) | tr -d '"'),$(2))
DOMAIN   = $(call env,DOMAIN,desigram.localhost)
PROJECT  = $(call env,PROJECT_NAME,desigram)
API_URL  = $(call env,PUBLIC_API_URL,https://api.$(DOMAIN):8443)
# все хосты за Traefik — для mkcert
DOMAINS ?= $(DOMAIN) $(addsuffix .$(DOMAIN),api traefik grafana prometheus jaeger rabbitmq mail)
BUF_IMG = $(PROJECT)/buf
BUF     = docker run --rm -v "$(CURDIR)/backend":/workspace $(BUF_IMG)
ANSIBLE = cd enviropment/ansible && ansible-playbook
OAPI_CODEGEN = go run github.com/oapi-codegen/oapi-codegen/v2/cmd/oapi-codegen@v2.8.0

.PHONY: cert configure dev prod deploy stop down logs ps proto proto-lint proto-breaking openapi new-service core-sh core-console core-lint core-test test e2e load

buf-image:            ## собрать образ генерации (buf + плагины)
	docker build -q -t $(BUF_IMG) enviropment/buf

# --- окружение (единая точка настройки: enviropment/ansible/inventory/group_vars) ---
cert:                 ## mkcert на все хосты домена из .env (или DOMAINS="a b c")
	./enviropment/certificate/install.sh $(DOMAINS)

configure:            ## сгенерировать enviropment/.env из group_vars
	$(ANSIBLE) playbooks/configure.yml -l local

dev: configure        ## локальный стек
	$(DEV) up -d --build --remove-orphans

prod:                 ## прод-стек на этой машине (обычно — через deploy)
	$(PROD) up -d --build --remove-orphans

deploy:               ## разворот на prod-серверы из inventory (docker + git + compose)
	$(ANSIBLE) playbooks/site.yml -l prod

stop:
	$(DEV) stop

down:
	$(DEV) down

logs:                 ## make logs S=core
	$(DEV) logs -f $(S)

ps:
	$(DEV) ps

# --- gRPC-контракты: backend/proto -> Go, PHP, Python ---
proto:
	$(BUF) generate

proto-lint:
	$(BUF) lint proto

proto-breaking:       ## что сломалось в контрактах относительно main (AGAINST=<ref>)
	@git -C backend cat-file -e $(or $(AGAINST),main):proto/buf.yaml 2>/dev/null \
		|| { echo "в $(or $(AGAINST),main) нет proto/ — сравнивать не с чем"; exit 0; }
	@rm -rf backend/.proto-against && mkdir -p backend/.proto-against
	@git -C backend archive $(or $(AGAINST),main) proto | tar -x -C backend/.proto-against
	@$(BUF) breaking proto --against .proto-against/proto; r=$$?; rm -rf backend/.proto-against; exit $$r

# --- HTTP-контракты: backend/openapi -> Go-типы (фронт: openapi-typescript) ---
openapi:
	cd backend/services/go && $(OAPI_CODEGEN) -config oapi-codegen.common.yaml ../../openapi/common.yaml
	cd backend/services/go && $(OAPI_CODEGEN) -config oapi-codegen.yaml ../../openapi/auth.yaml

new-service:          ## make new-service NAME=media
	./scripts/new-service.sh $(NAME)

# --- Symfony core ---
core-sh:
	$(DEV) exec core sh

core-console:         ## make core-console C="debug:router"
	$(DEV) exec core bin/console $(C)

core-lint:
	$(DEV) exec core composer lint

core-test:
	$(DEV) exec core composer test

# --- тесты ---
test:                 ## unit/интеграционные тесты всех сервисов (то же, что CI backend)
	$(DEV) exec core composer lint && $(DEV) exec core composer test
	cd backend/services/go && go vet ./... && go test ./...
	docker run --rm -v "$(CURDIR)/backend/services/python":/app -w /app ghcr.io/astral-sh/uv:python3.13-bookworm-slim \
		sh -c "uv sync --frozen --all-packages -q && uv run --no-sync ruff check . && uv run --no-sync pytest -q"

e2e:                  ## сквозная проверка поднятого стека (make dev перед этим)
	./scripts/e2e.sh

load:                 ## k6, 200 VU: make load [TARGET=https://api.<domain>]
	docker run --rm -i --network host -e TARGET=$(or $(TARGET),$(API_URL)) \
		-v "$(CURDIR)/tests/load":/scripts grafana/k6:latest run /scripts/api.js
