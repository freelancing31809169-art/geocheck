# syntax=docker/dockerfile:1

FROM --platform=$BUILDPLATFORM golang:1.26-alpine AS build

WORKDIR /src

COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod go mod download

COPY . .

ARG TARGETOS
ARG TARGETARCH
ARG VERSION=dev
ARG COMMIT=none
ARG DATE=unknown

RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} \
    go build -trimpath \
      -ldflags "-s -w \
        -X github.com/remnawave/geocheck/internal/version.Version=${VERSION} \
        -X github.com/remnawave/geocheck/internal/version.Commit=${COMMIT} \
        -X github.com/remnawave/geocheck/internal/version.Date=${DATE}" \
      -o /out/geocheck ./cmd/geocheck

FROM --platform=$BUILDPLATFORM alpine:3.22 AS caps
RUN apk add --no-cache libcap
COPY --from=build /out/geocheck /geocheck
RUN setcap cap_net_raw+p /geocheck && getcap /geocheck

FROM gcr.io/distroless/static-debian12:nonroot

LABEL org.opencontainers.image.title="geocheck" \
      org.opencontainers.image.description="IP geolocation and connectivity checker" \
      org.opencontainers.image.source="https://github.com/remnawave/geocheck" \
      org.opencontainers.image.licenses="MIT"

COPY --from=caps /geocheck /usr/local/bin/geocheck

USER nonroot:nonroot
ENTRYPOINT ["/usr/local/bin/geocheck"]
