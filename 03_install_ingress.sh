BASE_DIR="${BASE_DIR:-$HOME/talos-kvm}"
# Deploy to all clusters
for c in $BASE_DIR/cluster-*/kubeconfig; do
  CLUSTER_NUM=$(echo "$c" | grep -oP 'cluster-\K\d+')
  echo "=== Deploying to cluster-$CLUSTER_NUM ==="

  helm --kubeconfig="$c" repo add traefik https://traefik.github.io/charts >/dev/null 2>&1
  helm --kubeconfig="$c" repo update traefik >/dev/null 2>&1

  DOMAIN="cluster-${CLUSTER_NUM}.example.com"
  DASH_HOST="traefik.${DOMAIN}"

  helm --kubeconfig="$c" upgrade --install traefik traefik/traefik -n traefik --create-namespace --wait \
    --set ingressRoute.dashboard.enabled=true \
    --set ingressRoute.dashboard.matchRule="Host(\`${DASH_HOST}\`)" \
    --set ingressRoute.dashboard.entryPoints={web} \
    --set providers.kubernetesGateway.enabled=true \
    --set gateway.listeners.web.namespacePolicy.from=All
done
