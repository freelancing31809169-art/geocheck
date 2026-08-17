#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

VHS_IMAGE="${VHS_IMAGE:-ghcr.io/charmbracelet/vhs:latest}"
BIN_DIR=".vhs-bin"

have() { command -v "$1" >/dev/null 2>&1; }

target_arch() {
    if have docker; then
        docker image inspect "$VHS_IMAGE" -f '{{.Architecture}}' 2>/dev/null && return 0
    fi
    return 1
}

main() {
    have docker || {
        echo "record-demo: needs docker to run $VHS_IMAGE" >&2
        exit 1
    }

    docker image inspect "$VHS_IMAGE" >/dev/null 2>&1 || docker pull "$VHS_IMAGE"

    arch=$(target_arch || echo amd64)
    echo "==> building geocheck for linux/$arch"
    mkdir -p "$BIN_DIR" docs/img
    CGO_ENABLED=0 GOOS=linux GOARCH="$arch" \
        go build -trimpath -o "$BIN_DIR/geocheck" ./cmd/geocheck

    for tape in docs/tape/*.tape; do
        echo "==> recording $tape"
        docker run --rm \
            -v "$PWD:/vhs" \
            -w /vhs \
            --entrypoint vhs \
            "$VHS_IMAGE" "$tape"
    done

    rm -rf "$BIN_DIR"

    echo
    echo "==> done"
    ls -lh docs/img/*.gif
}

main "$@"
