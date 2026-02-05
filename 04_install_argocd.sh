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

helm --kubeconfig=$HOME/talos-kvm/cluster-1/kubeconfig upgrade --install --create-namespace argo argo/argo-cd -n argocd -f /tmp/argocd-values.yaml --wait

# export KUBECONFIG=/home/ds/talos-kvm/cluster-1/kubeconfig
# argocd admin initial-password -n argocd
# argocd login argocd.cluster-1.example.com
# argocd cluster add admin@cluster-1
# export KUBECONFIG=/home/ds/talos-kvm/cluster-2/kubeconfig
# argocd cluster add admin@cluster-2
