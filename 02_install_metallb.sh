BASE_DIR="${BASE_DIR:-$HOME/talos-kvm}"
# Deploy to all clusters
for c in $BASE_DIR/cluster-*/kubeconfig; do
  CLUSTER_NUM=$(echo "$c" | grep -oP 'cluster-\K\d+')
  echo "=== Deploying to cluster-$CLUSTER_NUM ==="

  # Map cluster number -> /24 inside 192.168.128.0/18
  # 192.168.(128 + CLUSTER_NUM - 1).0/24
  THIRD_OCTET=$((127 + CLUSTER_NUM))   # cluster-1 => 128, cluster-2 => 129, ...

  if [ "$THIRD_OCTET" -lt 128 ] || [ "$THIRD_OCTET" -gt 191 ]; then
    echo "ERROR: cluster-$CLUSTER_NUM maps outside 192.168.128.0/18 (third octet=$THIRD_OCTET)."
    continue
  fi

  POOL_CIDR="192.168.${THIRD_OCTET}.0/24"
  RANGE_START="192.168.${THIRD_OCTET}.1"
  RANGE_END="192.168.${THIRD_OCTET}.254"

  # Install MetalLB (idempotent)
  kubectl --kubeconfig="$c" apply -f https://raw.githubusercontent.com/metallb/metallb/v0.15.3/config/manifests/metallb-native.yaml
  kubectl --kubeconfig="$c" -n metallb-system wait --for=condition=Available deploy/controller --timeout=180s

  # Apply config
  kubectl --kubeconfig="$c" apply -f - <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: cluster-pool
  namespace: metallb-system
spec:
  addresses:
  - ${RANGE_START}-${RANGE_END}
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: l2-advertisement
  namespace: metallb-system
spec:
  ipAddressPools:
  - cluster-pool
EOF

  echo "MetalLB pool for cluster-$CLUSTER_NUM: ${POOL_CIDR} (${RANGE_START}-${RANGE_END})"
done
