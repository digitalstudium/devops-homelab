BASE_DIR="${BASE_DIR:-$HOME/talos-kvm}"

# Add color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Deploy to all clusters
for c in $BASE_DIR/cluster-*/kubeconfig; do
  CLUSTER_NUM=$(echo "$c" | grep -oP 'cluster-\K\d+')
  echo -e "${BLUE}=== Deploying for cluster-$CLUSTER_NUM ===${NC}"

  # Extract server URL from kubeconfig
  SERVER_URL=$(grep -E '^\s*server:\s*' "$c" | head -1 | sed 's/.*server:\s*//')

cat <<EOF | kubectl --kubeconfig=$BASE_DIR/cluster-1/kubeconfig apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: postgres-operator-cluster-$CLUSTER_NUM
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://opensource.zalando.com/postgres-operator/charts/postgres-operator
    targetRevision: 1.15.1
    chart: postgres-operator
  destination:
    server: $SERVER_URL
    namespace: postgres
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
      - ApplyOutOfSyncOnly=true
EOF

echo -e "${YELLOW}[operator] Waiting for ArgoCD sync for cluster-$CLUSTER_NUM...${NC}"
kubectl --kubeconfig=$BASE_DIR/cluster-1/kubeconfig wait --for=jsonpath='{.status.sync.status}'=Synced application/postgres-operator-cluster-$CLUSTER_NUM -n argocd --timeout=300s

echo -e "${YELLOW}[operator] Waiting deployment in cluster-$CLUSTER_NUM...${NC}"
kubectl --kubeconfig="$c" wait --for=condition=available --timeout=300s deployment/postgres-operator-cluster-$CLUSTER_NUM -n postgres

cat <<EOF | kubectl --kubeconfig=$BASE_DIR/cluster-1/kubeconfig apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: postgres-operator-ui-cluster-$CLUSTER_NUM
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://opensource.zalando.com/postgres-operator/charts/postgres-operator-ui
    targetRevision: 1.15.1
    chart: postgres-operator-ui
    helm:
      valuesObject:
        envs:
          targetNamespace: "*"
        ingress:
          enabled: true
          ingressClassName: "traefik"
          annotations:
            cert-manager.io/cluster-issuer: my-ca-issuer
          hosts:
            - host: postgres.cluster-$CLUSTER_NUM.example.com
              paths: ["/"]
          tls:
            - secretName: postgres-ui-tls
              hosts:
                - postgres.cluster-$CLUSTER_NUM.example.com
  destination:
    server: $SERVER_URL
    namespace: postgres
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - ServerSideApply=true
      - ApplyOutOfSyncOnly=true
      - CreateNamespace=true
EOF

echo -e "${YELLOW}[operator-ui] Waiting for ArgoCD sync for cluster-$CLUSTER_NUM...${NC}"
kubectl --kubeconfig=$BASE_DIR/cluster-1/kubeconfig wait --for=jsonpath='{.status.sync.status}'=Synced application/postgres-operator-ui-cluster-$CLUSTER_NUM -n argocd --timeout=300s

echo -e "${YELLOW}[operator-ui] Waiting for deployment in cluster-$CLUSTER_NUM...${NC}"
kubectl --kubeconfig="$c" wait --for=condition=available --timeout=300s deployment/postgres-operator-ui-cluster-$CLUSTER_NUM -n postgres

done
