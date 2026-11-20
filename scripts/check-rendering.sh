#!/usr/bin/env bash
# チャートのレンダリング結果が満たすべき条件を、ci/default-values.yaml でレンダリングした結果に対して確かめる。
# Pod のテンプレートにチャートのバージョン (helm.sh/chart) を入れない。ConfigMap の checksum は driver の Pod にだけ付ける。
# リリース名 carina でレンダリングすると Service が carina-app・carina-db・carina-vela になる。
# driver の PUPPIS_DRIVER_STATE は state のボリュームのマウント先と同じパスを指す。
# Pod が参照する PVC は、ci/default-values.yaml でも driver だけの ci/driver-only-values.yaml でも、すべてチャートが作る
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

# チャートのバージョンだけが変わっても driver の checksum は変わらない (変わるとバージョンを上げるたびに driver の Pod が作り直され、録画が中断する)
checksum_of() {
    printf '%s\n' "$1" | sed -n 's/^ *checksum\/config: *//p' | head -n 1
}
bumped=$(mktemp -d)
cp -r charts/pyxis "$bumped/pyxis"
sed -i 's/^version: .*/version: 99.99.99/; s/^appVersion: .*/appVersion: 99.99.99/' "$bumped/pyxis/Chart.yaml"
rebumped=$(helm template carina "$bumped/pyxis" -f charts/pyxis/ci/default-values.yaml)
rm -rf "$bumped"
if [ "$(checksum_of "$rendered")" != "$(checksum_of "$rebumped")" ]; then
    echo 'チャートのバージョンを変えただけで driver の checksum が変わる' >&2
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

# PUPPIS_DRIVER_STATE がボリュームの無いパスを指すと、driver は受信の記録を保存できず、エラーにもならない
state_env=$(printf '%s\n' "$rendered" | awk '/^ *- name: PUPPIS_DRIVER_STATE$/ { getline; print $2 }')
state_mount=$(printf '%s\n' "$rendered" | awk '/^ *- name: state$/ { getline; if ($1 == "mountPath:") print $2 }')
if [ -z "$state_env" ] || [ "$state_env" != "$state_mount" ]; then
    echo "driver の PUPPIS_DRIVER_STATE (${state_env:-無し}) が state のボリュームのマウント先 (${state_mount:-無し}) と違う" >&2
    status=1
fi

claims_not_made() {
    awk '
        /^---/ { kind = ""; name = "" }
        /^kind: / { kind = $2 }
        /^  name: / && name == "" { name = $2; if (kind == "PersistentVolumeClaim") made[name] = 1 }
        /^ *claimName: / { wanted[$2] = 1 }
        END { for (claim in wanted) if (!(claim in made)) print claim }
    ' | sort | tr '\n' ' '
}
driver_only=$(helm template carina charts/pyxis -f charts/pyxis/ci/driver-only-values.yaml)
for output in "$rendered" "$driver_only"; do
    missing=$(printf '%s\n' "$output" | claims_not_made)
    if [ -n "$missing" ]; then
        echo "Pod が参照する PVC をチャートが作っていない: $missing" >&2
        status=1
    fi
done

[ "$status" = 0 ] && echo 'レンダリング結果は条件をすべて満たしている'
exit "$status"
