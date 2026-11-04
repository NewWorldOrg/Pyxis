#!/usr/bin/env bash
# compose.yml、charts/pyxis/values.yaml、charts/pyxis/Chart.yaml の 3 か所に書いたイメージの版が同じかを確かめる。
# values.yaml と Chart.yaml のイメージはどれも compose.yml に無ければならず、compose.yml の carina・vela・postgres もその中に無ければならない
set -euo pipefail

cd "$(dirname "$0")/.."

compose_images() {
    sed -n 's/^ *image: *\(.*\)$/\1/p' compose.yml | tr -d "'\"" | sort -u
}

values_images() {
    awk '
        /^ *repository: / { repository = $2 }
        /^ *tag: / { print repository ":" $2 }
    ' charts/pyxis/values.yaml | sort -u
}

chart_images() {
    sed -n 's/^ *images\/[a-z-]*: *\(.*\)$/\1/p' charts/pyxis/Chart.yaml | sort -u
}

status=0

check_subset() {
    local label=$1
    local images=$2
    local image
    while IFS= read -r image; do
        [ -n "$image" ] || continue
        if ! compose_images | grep -qxF "$image"; then
            echo "$label の $image は compose.yml に無い" >&2
            status=1
        fi
    done <<<"$images"
}

check_subset 'values.yaml' "$(values_images)"
check_subset 'Chart.yaml' "$(chart_images)"

while IFS= read -r image; do
    case "$image" in
        */carina:* | */vela:* | postgres:*) ;;
        *) continue ;;
    esac
    if ! values_images | grep -qxF "$image"; then
        echo "compose.yml の $image は values.yaml に無い" >&2
        status=1
    fi
    if ! chart_images | grep -qxF "$image"; then
        echo "compose.yml の $image は Chart.yaml に無い" >&2
        status=1
    fi
done < <(compose_images)

if [ "$status" = 0 ]; then
    echo 'compose.yml、values.yaml、Chart.yaml のイメージの版は同じ'
    values_images
fi
exit "$status"
