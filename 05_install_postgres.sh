# Deploy to all clusters
for c in ~/talos-kvm/cluster-*/kubeconfig; do
  CLUSTER_NUM=$(echo "$c" | grep -oP 'cluster-\K\d+')
  echo "=== Deploying for cluster-$CLUSTER_NUM ==="

  # Extract server URL from kubeconfig
  SERVER_URL=$(grep -E '^\s*server:\s*' "$c" | head -1 | sed 's/.*server:\s*//')

cat <<EOF | kubectl --kubeconfig=$HOME/talos-kvm/cluster-1/kubeconfig apply -f -
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

cat <<EOF | kubectl --kubeconfig=$HOME/talos-kvm/cluster-1/kubeconfig apply -f -
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
        ingress:
          enabled: true
          ingressClassName: "traefik"
          hosts:
            - host: postgres.cluster-$CLUSTER_NUM.example.com
              paths: ["/"]
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
done
