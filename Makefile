COMPOSE = docker compose -f enviropment/docker-compose.yml
DEV     = $(COMPOSE) -f enviropment/docker-compose.dev.yml
PROD    = $(COMPOSE) -f enviropment/docker-compose.prod.yml
BUF_IMG = desigram/buf
BUF     = docker run --rm -v "$(CURDIR)/backend":/workspace $(BUF_IMG)
ANSIBLE = cd enviropment/ansible && ansible-playbook

.PHONY: cert configure dev prod deploy stop down logs ps proto proto-lint proto-breaking new-service core-sh core-console core-lint core-test

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
