#!/usr/bin/env bash
# Создаёт новый Go gRPC-микросервис: proto-контракт, Go-код, compose-файл, переменные окружения.
# Usage: scripts/new-service.sh <name>      (имя: [a-z][a-z0-9]*, например: media)
set -euo pipefail

NAME="${1:-}"
[[ "$NAME" =~ ^[a-z][a-z0-9]*$ ]] || { echo "usage: $0 <name>  (a-z0-9, с буквы)"; exit 1; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BACKEND="$ROOT/backend"
ENV="$ROOT/enviropment"
UPPER="$(echo "$NAME" | tr '[:lower:]' '[:upper:]')"
PASCAL="$(echo "${NAME:0:1}" | tr '[:lower:]' '[:upper:]')${NAME:1}"

[[ -e "$BACKEND/services/go/cmd/$NAME" ]] && { echo "сервис $NAME уже существует"; exit 1; }

log() { printf '==> %s\n' "$*"; }

# ---------- proto ----------
log "proto/desigram/$NAME/v1/$NAME.proto"
mkdir -p "$BACKEND/proto/desigram/$NAME/v1"
cat > "$BACKEND/proto/desigram/$NAME/v1/$NAME.proto" <<PROTO
syntax = "proto3";

package desigram.$NAME.v1;

option go_package = "github.com/snowaa-desigram/backend/services/go/gen/desigram/$NAME/v1;${NAME}v1";

service ${PASCAL}Service {
  rpc Ping(PingRequest) returns (PingResponse);
}

message PingRequest {
  string message = 1;
}

message PingResponse {
  string message = 1;
  string service = 2;
}
PROTO

# ---------- go (go-zero zrpc) ----------
log "services/go/cmd/$NAME, services/go/internal/$NAME"
mkdir -p "$BACKEND/services/go/cmd/$NAME/etc" "$BACKEND/services/go/internal/$NAME"
cat > "$BACKEND/services/go/internal/$NAME/config.go" <<GO
package $NAME

import "github.com/zeromicro/go-zero/zrpc"

type Config struct {
	zrpc.RpcServerConf
}
GO
cat > "$BACKEND/services/go/internal/$NAME/server.go" <<GO
package $NAME

import (
	"context"

	"github.com/zeromicro/go-zero/core/logx"

	${NAME}v1 "github.com/snowaa-desigram/backend/services/go/gen/desigram/$NAME/v1"
)

type Server struct {
	${NAME}v1.Unimplemented${PASCAL}ServiceServer
}

func NewServer() *Server {
	return &Server{}
}

func (s *Server) Ping(ctx context.Context, req *${NAME}v1.PingRequest) (*${NAME}v1.PingResponse, error) {
	logx.WithContext(ctx).Infof("$NAME: %s", req.GetMessage())

	return &${NAME}v1.PingResponse{
		Message: "pong: " + req.GetMessage(),
		Service: "$NAME",
	}, nil
}
GO
cat > "$BACKEND/services/go/cmd/$NAME/main.go" <<GO
package main

import (
	"flag"

	"github.com/zeromicro/go-zero/core/conf"
	"github.com/zeromicro/go-zero/core/service"
	"github.com/zeromicro/go-zero/zrpc"
	"google.golang.org/grpc"
	"google.golang.org/grpc/reflection"

	${NAME}v1 "github.com/snowaa-desigram/backend/services/go/gen/desigram/$NAME/v1"
	"github.com/snowaa-desigram/backend/services/go/internal/$NAME"
)

var configFile = flag.String("f", "etc/$NAME.yaml", "config file")

func main() {
	flag.Parse()

	var c $NAME.Config
	conf.MustLoad(*configFile, &c, conf.UseEnv())

	s := zrpc.MustNewServer(c.RpcServerConf, func(grpcServer *grpc.Server) {
		${NAME}v1.Register${PASCAL}ServiceServer(grpcServer, $NAME.NewServer())

		if c.Mode == service.DevMode || c.Mode == service.TestMode {
			reflection.Register(grpcServer)
		}
	})
	defer s.Stop()

	s.Start()
}
GO
cat > "$BACKEND/services/go/cmd/$NAME/etc/$NAME.yaml" <<YML
# go-zero zrpc: https://go-zero.dev/docs/tutorials/grpc/server/configuration
Name: $NAME.rpc
ListenOn: 0.0.0.0:50051
# dev|test|pre|pro — в dev/test включён grpc reflection (для grpcurl)
Mode: \${MODE}
Timeout: 5000
Log:
  Encoding: json
  Level: info
Prometheus:
  Host: 0.0.0.0
  Port: 9091
  Path: /metrics
Telemetry:
  Name: $NAME.rpc
  Endpoint: \${OTEL_ENDPOINT}
  Batcher: otlphttp
  Sampler: 1.0
YML

# ---------- compose ----------
log "enviropment/services/$NAME.yml"
cat > "$ENV/services/$NAME.yml" <<YML
# Go gRPC-микросервис: $NAME (внутренний, без Traefik)
services:
  $NAME:
    image: desigram/$NAME
    build:
      context: ../../backend/services/go
      dockerfile: ../../../enviropment/go/Dockerfile
      args:
        ENTRYPOINT_PATH: ./cmd/$NAME
        ENTRYPOINT_NAME: $NAME
    environment:
      MODE: \${GO_MODE:-pro}
      OTEL_ENDPOINT: \${OTEL_ENDPOINT:-}
    deploy:
      replicas: \${${UPPER}_REPLICAS:-1}
    networks:
      - app
    restart: unless-stopped
YML
perl -0pi -e "s|(include:\n(?:  - path: services/.*\n)*)|\$1  - path: services/$NAME.yml\n|" "$ENV/docker-compose.yml"
perl -0pi -e "s|(      TELEGRAM_GRPC_ADDR: telegram:50051\n)|\$1      ${UPPER}_GRPC_ADDR: $NAME:50051\n|" "$ENV/docker-compose.yml"

# ---------- единая точка настройки ----------
log "ansible group_vars + .env.example"
perl -0pi -e "s|(service_replicas:\n(?:  \w+: \d+\n)*)|\$1  $NAME: 1\n|" "$ENV/ansible/inventory/group_vars/all.yml"
perl -0pi -e "s|(TELEGRAM_REPLICAS=1\n)|\$1${UPPER}_REPLICAS=1\n|" "$ENV/.env.example"
printf '%s_GRPC_ADDR=127.0.0.1:50051\n' "$UPPER" >> "$BACKEND/core/.env"
perl -0pi -e "s|(job_name: go-services\n    static_configs:\n      - targets: \[[^\]]*)|\$1, \"$NAME:9091\"|" "$ENV/prometheus/prometheus.yml"

# ---------- генерация ----------
log "buf generate"
(cd "$ROOT" && make -s proto)
command -v go >/dev/null && (cd "$BACKEND/services/go" && go build ./...) || true

cat <<MSG

Готово: сервис "$NAME".
  proto:    backend/proto/desigram/$NAME/v1/$NAME.proto
  go:       backend/services/go/cmd/$NAME/{main.go,etc/$NAME.yaml}, internal/$NAME
  compose:  enviropment/services/$NAME.yml (подключён в docker-compose.yml)
  env:      ${UPPER}_GRPC_ADDR, ${UPPER}_REPLICAS

Дальше:
  1. Опиши RPC в proto, перегенерируй: make proto
  2. В core добавь порт + gRPC-адаптер (пример: src/Ping/Application/Port, src/Ping/Infrastructure/Grpc)
  3. make configure && make dev
MSG
