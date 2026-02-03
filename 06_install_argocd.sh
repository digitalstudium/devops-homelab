kubectl config use-context admin@cluster1
kubectl create namespace argocd
helm repo add argo https://argoproj.github.io/argo-helm
cat > /tmp/argocd-values.yaml << 'EOF'
configs:
  params:
    server.insecure: "true"

server:
  ingress:
    enabled: true
    ingressClassName: traefik
EOF

helm upgrade --install argo argo/argo-cd -n argocd -f /tmp/argocd-values.yaml


