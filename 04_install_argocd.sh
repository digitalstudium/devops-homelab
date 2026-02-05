BASE_DIR="${BASE_DIR:-$HOME/talos-kvm}"
helm repo add argo https://argoproj.github.io/argo-helm
cat > /tmp/argocd-values.yaml << 'EOF'
global:
  domain: argocd.cluster-1.example.com

configs:
  params:
    server.insecure: "true"

server:
  ingress:
    enabled: true
    ingressClassName: traefik
    tls: true
    annotations:
      cert-manager.io/cluster-issuer: my-ca-issuer
EOF

helm --kubeconfig=$BASE_DIR/cluster-1/kubeconfig upgrade --install --create-namespace argo argo/argo-cd -n argocd -f /tmp/argocd-values.yaml --wait

# export KUBECONFIG=/home/ds/talos-kvm/cluster-1/kubeconfig
# argocd admin initial-password -n argocd
# argocd login argocd.cluster-1.example.com
# argocd cluster add admin@cluster-1
# export KUBECONFIG=/home/ds/talos-kvm/cluster-2/kubeconfig
# argocd cluster add admin@cluster-2
#
export KUBECONFIG="$BASE_DIR/cluster-1/kubeconfig"
ARGOCD_SERVER="argocd.cluster-1.example.com"
INITIAL_PASSWORD=$(kubectl --kubeconfig=$BASE_DIR/cluster-1/kubeconfig \
  -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)

# Login (add --insecure if using self-signed certs)
argocd login "$ARGOCD_SERVER" \
  --username admin \
  --password "$INITIAL_PASSWORD" \
  --insecure  # Remove in production with valid TLS

# Add clusters
for cluster in cluster-1 cluster-2; do
  export KUBECONFIG="$BASE_DIR/$cluster/kubeconfig"
  argocd cluster add "admin@$cluster" --insecure
done
