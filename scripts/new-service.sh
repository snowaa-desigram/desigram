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

# ---------- go (go-zero zrpc), слои по openspec/specs/architecture-go-service ----------
log "services/go/cmd/$NAME, services/go/internal/$NAME/{transport,service}, tests/$NAME"
GOSVC="$BACKEND/services/go"
mkdir -p "$GOSVC/cmd/$NAME/etc" "$GOSVC/internal/$NAME/transport" "$GOSVC/internal/$NAME/service" "$GOSVC/tests/$NAME"
cat > "$GOSVC/internal/$NAME/config.go" <<GO
package $NAME

import "github.com/zeromicro/go-zero/zrpc"

// Config сервиса: zrpc.RpcServerConf даёт ListenOn, Mode, Log, Prometheus, Telemetry, Health и т.д.
type Config struct {
	zrpc.RpcServerConf
}
GO
cat > "$GOSVC/internal/$NAME/service/service.go" <<GO
package service

// Service — use-cases $NAME. Заглушка: отвечает pong.
type Service struct{}

func New() *Service { return &Service{} }

// Ping возвращает ответ на сообщение.
func (s *Service) Ping(message string) string {
	return "pong: " + message
}
GO
cat > "$GOSVC/internal/$NAME/transport/grpc.go" <<GO
package transport

import (
	"context"

	"github.com/zeromicro/go-zero/core/logx"

	${NAME}v1 "github.com/snowaa-desigram/backend/services/go/gen/desigram/$NAME/v1"
	"github.com/snowaa-desigram/backend/services/go/internal/$NAME/service"
)

// Server — gRPC-вход ${PASCAL}Service: pb → Service → pb.
type Server struct {
	${NAME}v1.Unimplemented${PASCAL}ServiceServer
	svc *service.Service
}

func NewServer(svc *service.Service) *Server {
	return &Server{svc: svc}
}

func (s *Server) Ping(ctx context.Context, req *${NAME}v1.PingRequest) (*${NAME}v1.PingResponse, error) {
	logx.WithContext(ctx).Infof("$NAME: %s", req.GetMessage())

	return &${NAME}v1.PingResponse{
		Message: s.svc.Ping(req.GetMessage()),
		Service: "$NAME",
	}, nil
}
GO
cat > "$GOSVC/cmd/$NAME/main.go" <<GO
package main

import (
	"flag"

	"github.com/zeromicro/go-zero/core/conf"
	zservice "github.com/zeromicro/go-zero/core/service"
	"github.com/zeromicro/go-zero/zrpc"
	"google.golang.org/grpc"
	"google.golang.org/grpc/reflection"

	${NAME}v1 "github.com/snowaa-desigram/backend/services/go/gen/desigram/$NAME/v1"
	"github.com/snowaa-desigram/backend/services/go/internal/$NAME"
	"github.com/snowaa-desigram/backend/services/go/internal/$NAME/service"
	"github.com/snowaa-desigram/backend/services/go/internal/$NAME/transport"
)

var configFile = flag.String("f", "etc/$NAME.yaml", "config file")

func main() {
	flag.Parse()

	var c $NAME.Config
	conf.MustLoad(*configFile, &c, conf.UseEnv())

	s := zrpc.MustNewServer(c.RpcServerConf, func(grpcServer *grpc.Server) {
		${NAME}v1.Register${PASCAL}ServiceServer(grpcServer, transport.NewServer(service.New()))

		if c.Mode == zservice.DevMode || c.Mode == zservice.TestMode {
			reflection.Register(grpcServer)
		}
	})
	defer s.Stop()

	s.Start()
}
GO
cat > "$GOSVC/tests/$NAME/service_test.go" <<GO
package ${NAME}_test

import (
	"testing"

	"github.com/snowaa-desigram/backend/services/go/internal/$NAME/service"
)

func TestServicePing(t *testing.T) {
	if got, want := service.New().Ping("hi"), "pong: hi"; got != want {
		t.Errorf("Ping = %q, want %q", got, want)
	}
}
GO
cat > "$GOSVC/tests/$NAME/transport_test.go" <<GO
package ${NAME}_test

import (
	"context"
	"testing"

	${NAME}v1 "github.com/snowaa-desigram/backend/services/go/gen/desigram/$NAME/v1"
	"github.com/snowaa-desigram/backend/services/go/internal/$NAME/service"
	"github.com/snowaa-desigram/backend/services/go/internal/$NAME/transport"
)

func TestPing(t *testing.T) {
	resp, err := transport.NewServer(service.New()).Ping(context.Background(), &${NAME}v1.PingRequest{Message: "hi"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got, want := resp.GetMessage(), "pong: hi"; got != want {
		t.Errorf("message = %q, want %q", got, want)
	}
}
GO
# depguard: service не импортирует transport (правило на сервис — pkg-префиксы не умеют «тот же сервис»)
perl -0pi -e "s|(        ping-service:\n          files: \[\"\*\*/internal/ping/service/\*\*\"\]\n          deny:\n(?:            .*\n)+)|\$1        $NAME-service:\n          files: [\"**/internal/$NAME/service/**\"]\n          deny:\n            - pkg: github.com/snowaa-desigram/backend/services/go/internal/$NAME/transport\n              desc: \"service не импортирует transport\"\n|" "$GOSVC/.golangci.yml"
cat > "$GOSVC/cmd/$NAME/etc/$NAME.yaml" <<YML
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
    image: \${PROJECT_NAME:-desigram}/$NAME
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
    security_opt: [no-new-privileges:true]
    restart: unless-stopped
YML
perl -0pi -e "s|(include:\n(?:  - path: services/.*\n)*)|\$1  - path: services/$NAME.yml\n|" "$ENV/docker-compose.yml"
perl -0pi -e "s|(      TELEGRAM_GRPC_ADDR: telegram:50051\n)|\$1      ${UPPER}_GRPC_ADDR: $NAME:50051\n|" "$ENV/docker-compose.yml"

# ---------- core: порт + gRPC-адаптер (GrpcGateway) + фейк для тестов ----------
log "core/src/$PASCAL/{Application/Port,Infrastructure/Grpc}, tests/Fake"
CORE="$BACKEND/core"
mkdir -p "$CORE/src/$PASCAL/Application/Port" "$CORE/src/$PASCAL/Infrastructure/Grpc" "$CORE/tests/Fake"
cat > "$CORE/src/$PASCAL/Application/Port/${PASCAL}Gateway.php" <<PHP
<?php

declare(strict_types=1);

namespace App\\$PASCAL\\Application\\Port;

/** Порт к Go-микросервису $NAME. Реализация — в Infrastructure. */
interface ${PASCAL}Gateway
{
    public function ping(string \$message): string;
}
PHP
cat > "$CORE/src/$PASCAL/Infrastructure/Grpc/Grpc${PASCAL}Gateway.php" <<PHP
<?php

declare(strict_types=1);

namespace App\\$PASCAL\\Infrastructure\\Grpc;

use App\\$PASCAL\\Application\\Port\\${PASCAL}Gateway;
use App\\Shared\\Infrastructure\\Grpc\\GrpcGateway;
use Desigram\\$PASCAL\\V1\\PingRequest;
use Desigram\\$PASCAL\\V1\\PingResponse;
use Desigram\\$PASCAL\\V1\\${PASCAL}ServiceClient;
use Symfony\\Component\\DependencyInjection\\Attribute\\Autowire;

final class Grpc${PASCAL}Gateway extends GrpcGateway implements ${PASCAL}Gateway
{
    private ${PASCAL}ServiceClient \$client;

    public function __construct(#[Autowire(env: '${UPPER}_GRPC_ADDR')] string \$address)
    {
        \$this->client = new ${PASCAL}ServiceClient(\$address, self::channelOptions());
    }

    public function ping(string \$message): string
    {
        /** @var PingResponse \$reply */
        \$reply = \$this->call(fn (): array => \$this->client->Ping((new PingRequest())->setMessage(\$message), [], self::callOptions())->wait());

        return \$reply->getMessage();
    }

    protected static function serviceName(): string
    {
        return '$NAME';
    }
}
PHP
cat > "$CORE/tests/Fake/InMemory${PASCAL}Gateway.php" <<PHP
<?php

declare(strict_types=1);

namespace App\\Tests\\Fake;

use App\\$PASCAL\\Application\\Port\\${PASCAL}Gateway;

final class InMemory${PASCAL}Gateway implements ${PASCAL}Gateway
{
    public function ping(string \$message): string
    {
        return 'pong: '.\$message;
    }
}
PHP
perl -0pi -e "s|(when\@test:\n    services:\n)|\$1        App\\\\Tests\\\\Fake\\\\InMemory${PASCAL}Gateway: ~\n        App\\\\$PASCAL\\\\Application\\\\Port\\\\${PASCAL}Gateway: '\@App\\\\Tests\\\\Fake\\\\InMemory${PASCAL}Gateway'\n|" "$CORE/config/services.yaml"

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
  go:       backend/services/go/cmd/$NAME/{main.go,etc/$NAME.yaml}, internal/$NAME/{config.go,transport,service}, tests/$NAME
            (слои — openspec/specs/architecture-go-service: transport → service → store; проверка — go test ./tests/architecture)
  compose:  enviropment/services/$NAME.yml (подключён в docker-compose.yml)
  env:      ${UPPER}_GRPC_ADDR, ${UPPER}_REPLICAS

Дальше:
  1. Опиши RPC в proto, перегенерируй: make proto
  2. В core порт + gRPC-адаптер уже созданы (src/$PASCAL/{Application/Port,Infrastructure/Grpc}, tests/Fake) — опиши реальные RPC
  3. make configure && make dev
MSG
