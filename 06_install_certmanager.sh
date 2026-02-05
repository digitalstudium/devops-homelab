BASE_DIR="${BASE_DIR:-$HOME/talos-kvm}"
# Add color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

deploy_cert_manager() {
  local c="$1"
  local CLUSTER_NUM="$2"

  echo -e "${BLUE}=== Deploying for cluster-$CLUSTER_NUM ===${NC}"

  # Extract server URL from kubeconfig
  SERVER_URL=$(grep -E '^\s*server:\s*' "$c" | head -1 | sed 's/.*server:\s*//')

cat <<EOF | kubectl --kubeconfig=$BASE_DIR/cluster-1/kubeconfig apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cert-manager-$CLUSTER_NUM
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://charts.jetstack.io
    targetRevision: v1.19.3
    chart: cert-manager
    helm:
      valuesObject:
        crds:
          enabled: true
  destination:
    server: $SERVER_URL
    namespace: cert-manager
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
      - ApplyOutOfSyncOnly=true
EOF

  echo -e "${YELLOW}Waiting for ArgoCD sync for cluster-$CLUSTER_NUM...${NC}"
  kubectl --kubeconfig=$BASE_DIR/cluster-1/kubeconfig wait --for=jsonpath='{.status.sync.status}'=Synced application/cert-manager-$CLUSTER_NUM -n argocd --timeout=300s

  echo -e "${YELLOW}Waiting for cert-manager deployments in cluster-$CLUSTER_NUM...${NC}"
  kubectl --kubeconfig="$c" wait --for=condition=available --timeout=300s deployment/cert-manager-$CLUSTER_NUM -n cert-manager
  kubectl --kubeconfig="$c" wait --for=condition=available --timeout=300s deployment/cert-manager-$CLUSTER_NUM-cainjector -n cert-manager
  kubectl --kubeconfig="$c" wait --for=condition=available --timeout=300s deployment/cert-manager-$CLUSTER_NUM-webhook -n cert-manager

  # echo -e "${YELLOW}Waiting for cert-manager startup API check job in cluster-$CLUSTER_NUM...${NC}"
  # # Wait for the job to exist first
  # timeout=60
  # while [ $timeout -gt 0 ]; do
  #   if kubectl --kubeconfig="$c" get job cert-manager-$CLUSTER_NUM-startupapicheck -n cert-manager &>/dev/null; then
  #     break
  #   fi
  #   sleep 2
  #   timeout=$((timeout - 2))
  # done

  # # Wait for the job to complete
  # kubectl --kubeconfig="$c" wait --for=condition=complete --timeout=300s job/cert-manager-$CLUSTER_NUM-startupapicheck -n cert-manager

  echo "Creating cert-manager resources in cluster-$CLUSTER_NUM..."
  # Apply with validate=false to bypass webhook temporarily
  cat <<EOF | kubectl --kubeconfig="$c" apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-issuer
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: my-selfsigned-ca
  namespace: cert-manager
spec:
  isCA: true
  commonName: my-selfsigned-ca
  secretName: root-secret
  privateKey:
    algorithm: ECDSA
    size: 256
  issuerRef:
    name: selfsigned-issuer
    kind: ClusterIssuer
    group: cert-manager.io
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: my-ca-issuer
spec:
  ca:
    secretName: root-secret
EOF

  echo -e "${YELLOW}Waiting for root-secret to be populated in cluster-$CLUSTER_NUM...${NC}"
  timeout=120
  while [ $timeout -gt 0 ]; do
    # Check if secret exists AND has ca.crt data
    CRT=$(kubectl --kubeconfig="$c" get secret -n cert-manager root-secret -o jsonpath='{.data.ca\.crt}' 2>/dev/null || echo "")
    
    if [ -n "$CRT" ] && [ "$CRT" != "null" ] && [ ${#CRT} -gt 4 ]; then  # base64 "null" or empty is invalid
      echo "$CRT" | base64 --decode > "cluster-$CLUSTER_NUM-ca.crt"
      echo -e "${GREEN}CA certificate extracted successfully${NC}"
      break
    fi
    
    sleep 2
    timeout=$((timeout - 2))
  done
  
  if [ $timeout -le 0 ]; then
    echo -e "${RED}ERROR: Timed out waiting for root-secret to be populated${NC}" >&2
    echo "Debug info:" >&2
    kubectl --kubeconfig="$c" describe certificate my-selfsigned-ca -n cert-manager >&2 || true
    kubectl --kubeconfig="$c" get secret -n cert-manager root-secret -o yaml >&2 || true
    exit 1
  fi
  echo -e "${GREEN}=== Finished cluster-$CLUSTER_NUM ===${NC}"
}

# Export the function for use in subshells
export -f deploy_cert_manager

# Deploy to all clusters in parallel
for c in $BASE_DIR/cluster-*/kubeconfig; do
  CLUSTER_NUM=$(echo "$c" | grep -oP 'cluster-\K\d+')
  deploy_cert_manager "$c" "$CLUSTER_NUM" &
done

# Wait for all background jobs to complete
wait

sudo cp *.crt /usr/local/share/ca-certificates/
sudo update-ca-certificates

echo -e "${GREEN}Cert manager deployed to all clusters successfully!${NC}"
