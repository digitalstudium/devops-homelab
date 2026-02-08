#!/bin/bash
set -euo pipefail

IFS='.' read -r o1 o2 o3 o4 <<< "$NETWORK"

for c in $BASE_DIR/cluster-*/kubeconfig; do
  CLUSTER_NUM=$(echo "$c" | grep -oP 'cluster-\K\d+')

  if (( CLUSTER_NUM < 1 || CLUSTER_NUM > 7 )); then
    echo "Ошибка: cluster-$CLUSTER_NUM выходит за пределы 1–7" >&2
    exit 1
  fi

  THIRD_OCTET=$((o3 + CLUSTER_NUM))
  RANGE_START="${o1}.${o2}.${THIRD_OCTET}.1"
  RANGE_END="${o1}.${o2}.${THIRD_OCTET}.254"

  echo "=== Configuring MetalLB for cluster-$CLUSTER_NUM ==="

  kubectl --kubeconfig="$c" apply -f https://raw.githubusercontent.com/metallb/metallb/v0.15.3/config/manifests/metallb-native.yaml
  kubectl --kubeconfig="$c" -n metallb-system wait --for=condition=available deploy/controller --timeout=180s

  kubectl --kubeconfig="$c" apply -f - <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
meta
  name: cluster-pool
  namespace: metallb-system
spec:
  addresses:
  - ${RANGE_START}-${RANGE_END}
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
meta
  name: l2-advertisement
  namespace: metallb-system
spec:
  ipAddressPools:
  - cluster-pool
EOF

   echo "MetalLB pool for cluster-$CLUSTER_NUM configured: (${RANGE_START}-${RANGE_END})"
done
