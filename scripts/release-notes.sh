#!/usr/bin/env bash
# GitHub Release の本文を書く。この版が固定するイメージの表と、前の版から driver が替わるかどうか。
# 引数は前の版のタグ (無ければ空)
set -euo pipefail

cd "$(dirname "$0")/.."

previous=${1:-}

image_of() {
    local ref=$1
    local part=$2
    if [ -z "$ref" ]; then
        return 0
    fi
    local image
    image=$(git show "${ref}:charts/pyxis/Chart.yaml" | sed -n "s/^ *images\/${part}: *//p")
    # v0.1.0 より前の Chart.yaml は driver を images/carina-driver と書いていた
    if [ -z "$image" ] && [ "$part" = puppis-driver ]; then
        image=$(git show "${ref}:charts/pyxis/Chart.yaml" | sed -n 's/^ *images\/carina-driver: *//p')
    fi
    printf '%s' "$image"
}

row() {
    local label=$1
    local part=$2
    local image
    image=$(sed -n "s/^ *images\/${part}: *//p" charts/pyxis/Chart.yaml)
    printf '| %s | `%s` |\n' "$label" "$image"
}

echo '| 部品 | イメージ |'
echo '| --- | --- |'
row 'Carina' carina-app
row 'Puppis (driver)' puppis-driver
row 'Vela' vela
row 'PostgreSQL' postgres
echo

driver_now=$(image_of HEAD puppis-driver)
driver_before=$(image_of "$previous" puppis-driver)
if [ -z "$previous" ]; then
    echo '最初の版。'
elif [ "$driver_now" = "$driver_before" ]; then
    echo "driver のイメージは ${previous} と同じ。更新しても driver は作り直されず、録画は続く。"
else
    echo "driver のイメージが ${previous} の \`${driver_before}\` から替わる。録画中とライブの視聴中を避けて更新する。"
fi
echo
echo "compose は \`git checkout ${GITHUB_REF_NAME:-$(git describe --tags --exact-match 2>/dev/null || echo HEAD)}\` して \`docker compose pull\` と \`docker compose up -d\`、Helm は \`helm upgrade carina oci://ghcr.io/newworldorg/charts/pyxis --version $(sed -n 's/^version: *//p' charts/pyxis/Chart.yaml) -n tv -f values.yaml\`。"
