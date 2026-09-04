COMPOSE = docker compose -f enviropment/docker-compose.yml

.PHONY: cert dev prod stop down

cert:
	./enviropment/certificate/install.sh $(DOMAINS)

dev:
	$(COMPOSE) -f enviropment/docker-compose.dev.yml up -d --build

prod:
	$(COMPOSE) -f enviropment/docker-compose.prod.yml up -d --build

stop:
	$(COMPOSE) -f enviropment/docker-compose.dev.yml stop

down:
	$(COMPOSE) -f enviropment/docker-compose.dev.yml down
