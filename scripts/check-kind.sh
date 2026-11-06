#!/usr/bin/env bash
# 今の kubectl の context (kind) に、既定の値と ci/kind-sizes.yaml でチャートを入れ、
# app の /api/health と vela の /login が 200 を返し、app が driver の口 (/events) につないだことを確かめる。
# 終わったらリリースと名前空間を消す
set -euo pipefail

cd "$(dirname "$0")/.."

namespace=${PYXIS_KIND_NAMESPACE:-pyxis-check}
release=carina
app_port=${PYXIS_KIND_APP_PORT:-18080}
vela_port=${PYXIS_KIND_VELA_PORT:-13000}
forwards=()

cleanup() {
    for pid in "${forwards[@]}"; do
        kill "$pid" 2>/dev/null || true
    done
    if [ "${PYXIS_KIND_KEEP:-}" != 1 ]; then
        helm uninstall "$release" -n "$namespace" --wait --timeout 5m >/dev/null 2>&1 || true
        kubectl delete namespace "$namespace" --wait=false >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

describe_failure() {
    echo '== pods'
    kubectl -n "$namespace" get pods -o wide
    echo '== events'
    kubectl -n "$namespace" get events --sort-by=.lastTimestamp | tail -n 40
    for part in driver app vela db; do
        echo "== logs ${release}-${part}"
        kubectl -n "$namespace" logs "deploy/${release}-${part}" --all-containers --tail=60 2>/dev/null \
            || kubectl -n "$namespace" logs "statefulset/${release}-${part}" --all-containers --tail=60 2>/dev/null \
            || true
    done
}

kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
# driver は privileged で動く
kubectl label namespace "$namespace" pod-security.kubernetes.io/enforce=privileged --overwrite >/dev/null

if ! helm upgrade --install "$release" charts/pyxis -n "$namespace" \
    -f charts/pyxis/ci/default-values.yaml -f charts/pyxis/ci/kind-sizes.yaml \
    --wait --timeout 10m; then
    describe_failure
    exit 1
fi

kubectl -n "$namespace" port-forward "svc/${release}-app" "${app_port}:8080" >/dev/null 2>&1 &
forwards+=("$!")
kubectl -n "$namespace" port-forward "svc/${release}-vela" "${vela_port}:3000" >/dev/null 2>&1 &
forwards+=("$!")

health=''
login=''
for _ in $(seq 1 60); do
    health=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${app_port}/api/health" || true)
    login=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${vela_port}/login" || true)
    if [ "$health" = 200 ] && [ "$login" = 200 ]; then
        break
    fi
    sleep 1
done
echo "health=${health} login=${login}"
if [ "$health" != 200 ] || [ "$login" != 200 ]; then
    describe_failure
    exit 1
fi
curl -s "http://127.0.0.1:${app_port}/api/health"
echo

# app は driver の口につなぐと、まず /events を購読する。driver の要求のログにそれが残る
subscribed=''
for _ in $(seq 1 60); do
    if kubectl -n "$namespace" logs "deploy/${release}-driver" --tail=-1 | grep -q 'GET http://driver/events'; then
        subscribed=yes
        break
    fi
    sleep 1
done
if [ -z "$subscribed" ]; then
    echo 'app が driver の /events を購読した記録が driver のログに無い' >&2
    describe_failure
    exit 1
fi
echo 'app が driver の /events を購読した'

kubectl -n "$namespace" get pods -o custom-columns='NAME:.metadata.name,READY:.status.containerStatuses[*].ready,PHASE:.status.phase' --no-headers
