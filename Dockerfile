# syntax=docker/dockerfile:1

# Compile on the build host, including when the target image is ARM64.
FROM --platform=$BUILDPLATFORM golang:1.27.3-alpine AS builder
WORKDIR /app
ENV CGO_ENABLED=0 GOEXPERIMENT=jsonv2
COPY go.mod go.sum ./
RUN go mod download
COPY . .
ARG TARGETOS
ARG TARGETARCH
ARG TARGETVARIANT
RUN --mount=type=cache,target=/root/.cache/go-build \
    if [ "${TARGETARCH}" = "arm" ]; then export GOARM="${TARGETVARIANT#v}"; fi; \
    GOOS=${TARGETOS} GOARCH=${TARGETARCH} \
    go build -mod=readonly -trimpath -o V2bX -tags "sing xray hysteria2 with_quic with_grpc with_utls with_wireguard with_acme with_gvisor" .

# Release
FROM alpine
# 安装必要的工具包
RUN apk --no-cache add tzdata ca-certificates \
    && cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime \
    && mkdir -p /etc/V2bX
COPY --from=builder /app/V2bX /usr/local/bin/V2bX

ENTRYPOINT [ "V2bX", "server", "--config", "/etc/V2bX/config.json"]
