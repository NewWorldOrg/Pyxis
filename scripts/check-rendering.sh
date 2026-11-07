#!/usr/bin/env bash
# チャートの描き方の決まりを、既定の値で描いた結果に対して確かめる。
# Pod のテンプレートにチャートの版 (helm.sh/chart) を入れない。ConfigMap の checksum は driver の Pod にだけ付ける。
# リリース名 carina で描くと Service が carina-app・carina-db・carina-vela になる
set -euo pipefail

cd "$(dirname "$0")/.."

rendered=$(helm template carina charts/pyxis -f charts/pyxis/ci/default-values.yaml)

status=0

in_pod_templates() {
    awk '/^---/ { inside = 0 } /^  template:/ { inside = 1 } inside'
}

if printf '%s\n' "$rendered" | in_pod_templates | grep -q 'helm.sh/chart'; then
    echo 'Pod のテンプレートに helm.sh/chart のラベルがある' >&2
    status=1
fi

checksum_owners=$(printf '%s\n' "$rendered" | awk '
    /^---/ { name = "" }
    /^  name: / && name == "" { name = $2 }
    /checksum\/config/ { print name }
')
if [ "$checksum_owners" != 'carina-driver' ]; then
    echo "ConfigMap の checksum を持つのは carina-driver だけのはずが: ${checksum_owners:-(無し)}" >&2
    status=1
fi

# チャートの版だけが変わっても driver の checksum は変わらない (変わると版を上げるたびに driver が作り直され、録画が切れる)
checksum_of() {
    printf '%s\n' "$1" | sed -n 's/^ *checksum\/config: *//p' | head -n 1
}
bumped=$(mktemp -d)
cp -r charts/pyxis "$bumped/pyxis"
sed -i 's/^version: .*/version: 99.99.99/; s/^appVersion: .*/appVersion: 99.99.99/' "$bumped/pyxis/Chart.yaml"
rebumped=$(helm template carina "$bumped/pyxis" -f charts/pyxis/ci/default-values.yaml)
rm -rf "$bumped"
if [ "$(checksum_of "$rendered")" != "$(checksum_of "$rebumped")" ]; then
    echo 'チャートの版を変えただけで driver の checksum が変わる' >&2
    status=1
fi
reconfigured=$(helm template carina charts/pyxis -f charts/pyxis/ci/default-values.yaml --set driver.config.shutdownGraceHours=7)
if [ "$(checksum_of "$rendered")" = "$(checksum_of "$reconfigured")" ]; then
    echo 'driver.json を変えても driver の checksum が変わらない' >&2
    status=1
fi

services=$(printf '%s\n' "$rendered" | awk '
    /^---/ { kind = ""; name = "" }
    /^kind: / { kind = $2 }
    /^  name: / && name == "" { name = $2; if (kind == "Service") print name }
' | sort | tr '\n' ' ')
if [ "$services" != 'carina-app carina-db carina-vela ' ]; then
    echo "Service の名前が違う: $services" >&2
    status=1
fi

[ "$status" = 0 ] && echo '描き方の決まりは守られている'
exit "$status"
