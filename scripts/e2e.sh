#!/usr/bin/env bash
# E2E: реальная цепочка HTTP → core → gRPC → Go/Python → RabbitMQ → core-worker, плюс auth → SMTP (mailpit) → JWT → core.
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

# ---- auth: регистрация → код из mailpit → токены → core доверяет JWT (из контейнера core: auth:8080, mailpit:8025) ----
auth_email="e2e-$(date +%s)@example.com"
auth_pass="e2e-password-1"
auth_new_pass="e2e-password-2"
# api <method> <path> [json] [bearer] → тело; http-код в $code
api() {
  local method="$1" path="$2" body="${3:-}" bearer="${4:-}" out
  out=$($CORE curl -sS -o - -w '\n%{http_code}' -X "$method" "http://auth:8080$path" \
    -H 'Content-Type: application/json' ${bearer:+-H "Authorization: Bearer $bearer"} ${body:+-d "$body"})
  code="${out##*$'\n'}"; printf '%s' "${out%$'\n'*}"
}
# mail_code <email> — последний 6-значный код из письма в mailpit (ждём до 10 с)
mail_code() {
  local id
  for _ in $(seq 1 20); do
    id=$($CORE curl -sS "http://mailpit:8025/api/v1/search?query=to:$1" | jq -r '.messages[0].ID // empty')
    [[ -n "$id" ]] && { $CORE curl -sS "http://mailpit:8025/api/v1/message/$id" | jq -r .Text | grep -oE '[0-9]{6}' | head -1; return; }
    sleep 0.5
  done
}
t_auth_health()   { $CORE curl -fsS http://auth:8080/health | grep -q '"ok"'; }
t_register()      { api POST /api/auth/register "{\"email\":\"$auth_email\",\"password\":\"$auth_pass\"}" >/dev/null; [[ $code == 202 ]]; }
t_confirm() {
  local c; c=$(mail_code "$auth_email"); [[ -n "$c" ]] || return 1
  local body; body=$(api POST /api/auth/register/confirm "{\"email\":\"$auth_email\",\"code\":\"$c\"}")
  [[ $code == 200 ]] || return 1
  access=$(jq -r .accessToken <<<"$body"); refresh=$(jq -r .refreshToken <<<"$body"); [[ -n "$access" && -n "$refresh" ]]
}
t_me()            { api GET /api/auth/me "" "$access" | grep -q "$auth_email" && [[ $code == 200 ]]; }
t_me_noauth()     { api GET /api/auth/me >/dev/null; [[ $code == 401 ]]; }
t_login()         { api POST /api/auth/login "{\"email\":\"$auth_email\",\"password\":\"$auth_pass\"}" >/dev/null; [[ $code == 200 ]]; }
t_login_wrong()   { api POST /api/auth/login "{\"email\":\"$auth_email\",\"password\":\"nope-nope\"}" >/dev/null; [[ $code == 401 ]]; }
t_refresh() {
  local body; body=$(api POST /api/auth/refresh "{\"refreshToken\":\"$refresh\"}"); [[ $code == 200 ]] || return 1
  local old="$refresh"; refresh=$(jq -r .refreshToken <<<"$body"); access=$(jq -r .accessToken <<<"$body")
  api POST /api/auth/refresh "{\"refreshToken\":\"$old\"}" >/dev/null; [[ $code == 401 ]]   # старый — одноразовый
}
t_forgot()        { api POST /api/auth/password/forgot "{\"email\":\"$auth_email\"}" >/dev/null; [[ $code == 202 ]]; }
t_reset() {
  sleep 1  # cooldown кода общий по назначению, письмо уже второе — берём свежее
  local c; c=$(mail_code "$auth_email"); [[ -n "$c" ]] || return 1
  local body; body=$(api POST /api/auth/password/reset "{\"email\":\"$auth_email\",\"code\":\"$c\",\"newPassword\":\"$auth_new_pass\"}")
  [[ $code == 200 ]] || return 1
  access=$(jq -r .accessToken <<<"$body"); refresh=$(jq -r .refreshToken <<<"$body")
  api POST /api/auth/login "{\"email\":\"$auth_email\",\"password\":\"$auth_pass\"}" >/dev/null; [[ $code == 401 ]]  # старый пароль не работает
}
t_logout()        { api POST /api/auth/logout "{\"refreshToken\":\"$refresh\"}" "$access" >/dev/null; [[ $code == 204 ]]; }
t_core_me()       { $CORE curl -sS -H "Authorization: Bearer $access" localhost:8080/api/me | grep -q "$auth_email"; }
t_core_me_noauth(){ $CORE curl -sS -o /dev/null -w '%{http_code}' localhost:8080/api/me | grep -q 401; }

echo "core"
check "GET /health → 200"                 t_health
check "GET /api/ping → Go ping"           t_ping
echo "grpc"
check "ping: health SERVING"              t_ping_grpc
check "telegram: health SERVING"          t_tg_grpc
echo "queue"
check "POST /api/telegram/photo → 202"    t_post_photo
check "core-worker → RabbitMQ → Python получил SendPhoto" t_worker
echo "auth"
check "GET /health → 200"                          t_auth_health
check "POST /register → 202, письмо в mailpit"     t_register
check "POST /register/confirm (код из письма) → токены" t_confirm
check "GET /me с JWT → email"                      t_me
check "GET /me без JWT → 401"                      t_me_noauth
check "POST /login → 200"                          t_login
check "POST /login с неверным паролем → 401"       t_login_wrong
check "POST /refresh → новая пара, старый refresh → 401" t_refresh
check "POST /password/forgot → 202"                t_forgot
check "POST /password/reset (код из письма) → 200, старый пароль → 401" t_reset
check "POST /logout → 204"                         t_logout
echo "core ← auth"
check "GET /api/me в core с JWT от auth → email"   t_core_me
check "GET /api/me в core без JWT → 401"           t_core_me_noauth

echo
echo "passed: $pass, failed: $fail"
[[ $fail -eq 0 ]]
