#!/bin/sh
set -eu

IMAGE="${GEOCHECK_IMAGE:-remnawave/geocheck:ing}"
REPO="${GEOCHECK_REPO:-remnawave/geocheck}"

say() { printf '%s\n' "$*" >&2; }
die() { printf 'geocheck: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

clear_screen() {
    [ -t 1 ] || return 0

    if have clear; then
        clear 2>/dev/null && return 0
    fi
    if have tput; then
        tput clear 2>/dev/null && return 0
    fi
    printf '\033[3J\033[H\033[2J'
}

run_container() {
    engine=$1
    shift

    tty_flags=""
    use_tty_stdin=0
    if [ -t 1 ]; then
        if [ -t 0 ]; then
            tty_flags="-it"
        elif [ -r /dev/tty ] && [ -w /dev/tty ]; then
            tty_flags="-it"
            use_tty_stdin=1
        fi
    fi

    net_flags=""
    if [ "$(uname -s)" = "Linux" ]; then
        net_flags="--network host"
    fi

    cap_flags="--cap-add=NET_RAW"

    pulled=0
    if ! "$engine" image inspect "$IMAGE" >/dev/null 2>&1; then
        say "→ pulling $IMAGE"
        "$engine" pull "$IMAGE" >&2 || die "could not pull $IMAGE"
        pulled=1
    fi

    trap 'discard_image "$engine" "$pulled"' INT TERM

    clear_screen

    set +e
    if [ "$use_tty_stdin" -eq 1 ]; then
        # shellcheck disable=SC2086
        "$engine" run --rm $tty_flags $net_flags $cap_flags "$IMAGE" "$@" < /dev/tty
    else
        # shellcheck disable=SC2086
        "$engine" run --rm $tty_flags $net_flags $cap_flags "$IMAGE" "$@"
    fi
    status=$?
    set -e

    trap - INT TERM
    discard_image "$engine" "$pulled"
    exit "$status"
}

discard_image() {
    [ "$2" -eq 1 ] || return 0
    [ -z "${GEOCHECK_KEEP_IMAGE:-}" ] || return 0
    "$1" rmi "$IMAGE" >/dev/null 2>&1 || true
}

fetch() {
    if have curl; then
        curl -fsSL "$1"
    else
        wget -qO- "$1"
    fi
}

platform_asset() {
    asset_version=$1

    case "$(uname -s)" in
        Linux)  asset_os="linux" ;;
        Darwin) asset_os="darwin" ;;
        *)      return 1 ;;
    esac

    case "$(uname -m)" in
        x86_64 | amd64)  asset_arch="amd64" ;;
        aarch64 | arm64) asset_arch="arm64" ;;
        *)               return 1 ;;
    esac

    [ "$asset_os" = "darwin" ] && asset_arch="all"

    printf 'geocheck_%s_%s_%s.tar.gz' "$asset_version" "$asset_os" "$asset_arch"
}

run_download() {
    have curl || have wget || die "need curl or wget to download the release"
    have tar || die "need tar to unpack the release"

    say "→ no container runtime; fetching the release binary"

    tag=$(fetch "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null \
        | sed -n 's/.*"tag_name" *: *"\([^"]*\)".*/\1/p' | head -1) || tag=""
    [ -n "$tag" ] || die "could not find a release for $REPO.
  If the repository is private or has no release yet, install one of:
      docker            https://docs.docker.com/get-docker/
      go install github.com/$REPO/cmd/geocheck@latest"

    version=${tag#v}
    asset=$(platform_asset "$version") \
        || die "no published build for $(uname -s)/$(uname -m).
  Build from source instead:
      go install github.com/$REPO/cmd/geocheck@latest"

    tmp=$(mktemp -d 2>/dev/null || mktemp -d -t geocheck)
    trap 'rm -rf "$tmp"' EXIT INT TERM

    base="https://github.com/$REPO/releases/download/$tag"
    say "→ downloading $asset ($tag)"
    fetch "$base/$asset" > "$tmp/$asset" || die "download failed: $base/$asset"

    if have sha256sum || have shasum; then
        if fetch "$base/geocheck_${version}_checksums.txt" > "$tmp/checksums.txt" 2>/dev/null; then
            expected=$(sed -n "s/^\([0-9a-f]*\)  *$asset\$/\1/p" "$tmp/checksums.txt" | head -1)
            if [ -n "$expected" ]; then
                if have sha256sum; then
                    actual=$(sha256sum "$tmp/$asset" | cut -d' ' -f1)
                else
                    actual=$(shasum -a 256 "$tmp/$asset" | cut -d' ' -f1)
                fi
                [ "$actual" = "$expected" ] \
                    || die "checksum mismatch for $asset; refusing to run it"
                say "→ checksum verified"
            fi
        fi
    fi

    tar -xzf "$tmp/$asset" -C "$tmp" || die "could not unpack $asset"
    [ -x "$tmp/geocheck" ] || chmod +x "$tmp/geocheck" 2>/dev/null || true
    [ -f "$tmp/geocheck" ] || die "the archive did not contain a geocheck binary"

    clear_screen
    set +e
    "$tmp/geocheck" "$@"
    status=$?
    set -e
    exit "$status"
}

main() {
    for candidate in docker podman; do
        if have "$candidate"; then
            run_container "$candidate" "$@"
        fi
    done

    run_download "$@"
}

main "$@"