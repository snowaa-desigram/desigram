FROM golang:alpine AS builder

LABEL stage=gobuilder

ARG ENTRYPOINT_PATH
ARG ENTRYPOINT_NAME
ARG PORT

ENV CGO_ENABLED=0 GOOS=linux GOARCH=amd64

RUN echo ${ENTRYPOINT_PATH} ${ENTRYPOINT_NAME} ${PORT}

WORKDIR /build

RUN echo "building code..."

COPY go.mod ./
COPY go.sum* ./
RUN go mod download

COPY . .

RUN go build -o ${ENTRYPOINT_NAME} ${ENTRYPOINT_PATH}

FROM alpine:latest AS runner

ARG ENTRYPOINT_NAME
ARG PORT

WORKDIR /app

RUN echo "copying binary..."

COPY --from=builder /build/${ENTRYPOINT_NAME} /app/${ENTRYPOINT_NAME}

RUN echo "running server..."

CMD ["./server"]

EXPOSE ${PORT}