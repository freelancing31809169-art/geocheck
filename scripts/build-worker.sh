#!/bin/sh

set -eu

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
src="$root/scripts/geocheck.sh"
tmpl="$root/web/worker.js"
out="$root/web/dist/worker.js"

[ -f "$src" ] || { echo "missing $src" >&2; exit 1; }
[ -f "$tmpl" ] || { echo "missing $tmpl" >&2; exit 1; }

mkdir -p "$root/web/dist"

if command -v jq >/dev/null 2>&1; then
    literal=$(jq -Rs . < "$src")
else
    literal=$(python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' < "$src")
fi

printf '%s' "$literal" > "$root/web/dist/.literal"

awk '
    FNR == NR { lit = lit $0; next }
    {
        idx = index($0, "__GEOCHECK_SH__")
        if (idx == 0) { print; next }
        printf "%s%s%s\n", \
            substr($0, 1, idx - 1), \
            lit, \
            substr($0, idx + length("__GEOCHECK_SH__"))
    }
' "$root/web/dist/.literal" "$tmpl" > "$out"
rm -f "$root/web/dist/.literal"

if grep -q '__GEOCHECK_SH__' "$out"; then
    echo "placeholder was not replaced in $out" >&2
    exit 1
fi

if command -v node >/dev/null 2>&1; then
    node --check "$out" || { echo "generated worker is not valid JavaScript" >&2; exit 1; }
fi

echo "built $out ($(wc -c < "$out" | tr -d ' ') bytes)"
