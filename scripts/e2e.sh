#!/usr/bin/env bash
# E2E: реальная цепочка HTTP → core → gRPC → Go/Python → RabbitMQ → core-worker.
# Стек должен быть поднят (make dev или см. .github/workflows/e2e.yml). Traefik/TLS не нужны — ходим внутрь сети.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEV="docker compose -f $ROOT/enviropment/docker-compose.yml -f $ROOT/enviropment/docker-compose.dev.yml"
CORE="$DEV exec -T core"
GRPCURL="docker run --rm --network desigram fullstorydev/grpcurl:latest -plaintext"

pass=0; fail=0
check() {
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then printf '  \033[32m✔\033[0m %s\n' "$name"; pass=$((pass+1))
  else printf '  \033[31m✘\033[0m %s\n' "$name"; fail=$((fail+1)); fi
}

# ---- проверки ----
t_health()      { $CORE curl -fsS localhost:8080/health | grep -q '"ok"'; }
t_ping()        { $CORE curl -fsS 'localhost:8080/api/ping?message=e2e' | grep -q 'pong: e2e'; }
t_ping_grpc()   { $GRPCURL ping:50051 grpc.health.v1.Health/Check | grep -q SERVING; }
t_tg_grpc()     { $GRPCURL telegram:50051 grpc.health.v1.Health/Check | grep -q SERVING; }

marker="e2e-$(date +%s)"
t_post_photo() {
  $CORE sh -c "printf png > /tmp/p.png && curl -fsS -o /dev/null -w '%{http_code}' \
    -F chat_id=1 -F caption=$marker -F photo=@/tmp/p.png localhost:8080/api/telegram/photo" | grep -q 202
}
t_worker() {
  for _ in $(seq 1 30); do
    $DEV logs --since 5m telegram 2>/dev/null | grep -q "caption='$marker'" && return 0
    sleep 1
  done
  return 1
}

echo "core"
check "GET /health → 200"                 t_health
check "GET /api/ping → Go ping"           t_ping
echo "grpc"
check "ping: health SERVING"              t_ping_grpc
check "telegram: health SERVING"          t_tg_grpc
echo "queue"
check "POST /api/telegram/photo → 202"    t_post_photo
check "core-worker → RabbitMQ → Python получил SendPhoto" t_worker

echo
echo "passed: $pass, failed: $fail"
[[ $fail -eq 0 ]]
