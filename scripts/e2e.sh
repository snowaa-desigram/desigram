#!/usr/bin/env bash
# E2E: реальная цепочка HTTP → core → gRPC → Go/Python → RabbitMQ → core-worker.
# Стек должен быть поднят (make dev или см. .github/workflows/e2e.yml). Traefik/TLS не нужны — ходим внутрь сети.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEV="docker compose -f $ROOT/enviropment/docker-compose.yml -f $ROOT/enviropment/docker-compose.dev.yml"
GRPCURL="docker run --rm --network desigram fullstorydev/grpcurl:latest -plaintext"

pass=0; fail=0
ok()   { printf '  \033[32m✔\033[0m %s\n' "$*"; pass=$((pass+1)); }
bad()  { printf '  \033[31m✘\033[0m %s\n' "$*"; fail=$((fail+1)); }
check() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$name"; else bad "$name"; fi; }

core() { $DEV exec -T core "$@"; }

echo "core"
check "GET /health → 200"        sh -c "core curl -fsS localhost:8080/health | grep -q '\"ok\"'"
check "GET /api/ping → Go ping"  sh -c "core curl -fsS 'localhost:8080/api/ping?message=e2e' | grep -q 'pong: e2e'"

echo "grpc"
check "ping: health SERVING"     sh -c "$GRPCURL ping:50051 grpc.health.v1.Health/Check | grep -q SERVING"
check "telegram: health SERVING" sh -c "$GRPCURL telegram:50051 grpc.health.v1.Health/Check | grep -q SERVING"

echo "queue"
marker="e2e-$(date +%s)"
check "POST /api/telegram/photo → 202" \
  sh -c "core sh -c 'printf png > /tmp/p.png && curl -fsS -o /dev/null -w %{http_code} -F chat_id=1 -F caption=$marker -F photo=@/tmp/p.png localhost:8080/api/telegram/photo' | grep -q 202"
check "core-worker обработал команду (Python получил SendPhoto)" \
  sh -c "for i in \$(seq 1 20); do $DEV logs --since 2m telegram 2>/dev/null | grep -q \"caption='$marker'\" && exit 0; sleep 1; done; exit 1"

echo
echo "passed: $pass, failed: $fail"
[[ $fail -eq 0 ]]
