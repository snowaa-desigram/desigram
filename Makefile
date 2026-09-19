COMPOSE = docker compose -f enviropment/docker-compose.yml
DEV     = $(COMPOSE) -f enviropment/docker-compose.dev.yml
PROD    = $(COMPOSE) -f enviropment/docker-compose.prod.yml
BUF_IMG = desigram/buf
BUF     = docker run --rm -v "$(CURDIR)/backend":/workspace $(BUF_IMG)
ANSIBLE = cd enviropment/ansible && ansible-playbook
OAPI_CODEGEN = go run github.com/oapi-codegen/oapi-codegen/v2/cmd/oapi-codegen@v2.8.0

.PHONY: cert configure dev prod deploy stop down logs ps proto proto-lint proto-breaking openapi new-service core-sh core-console core-lint core-test test e2e load

buf-image:            ## собрать образ генерации (buf + плагины)
	docker build -q -t $(BUF_IMG) enviropment/buf

# --- окружение (единая точка настройки: enviropment/ansible/inventory/group_vars) ---
cert:
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

load:                 ## k6, 200 VU: make load TARGET=https://api.desigram.localhost:8443
	docker run --rm -i --network host -e TARGET=$(or $(TARGET),https://api.desigram.localhost:8443) \
		-v "$(CURDIR)/tests/load":/scripts grafana/k6:latest run /scripts/api.js
