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
  name: local-path-provisioner-cluster-$CLUSTER_NUM
  namespace: argocd
spec:
  project: default
  source:
    path: deploy/chart/local-path-provisioner
    repoURL: https://github.com/rancher/local-path-provisioner.git
    targetRevision: v0.0.34
    helm:
      valuesObject:
        storageClass:
          create: true
          name: local-path
          defaultClass: true
          reclaimPolicy: Retain
          defaultVolumeType: local
        nodePathMap:
          - node: DEFAULT_PATH_FOR_NON_LISTED_NODES
            paths: ["/var/mnt/local-path-provisioner"]
  destination:
    server: $SERVER_URL
    namespace: local-path-storage
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
    managedNamespaceMetadata:
      labels:
        pod-security.kubernetes.io/enforce: privileged  # needed for creation of helper pod with HostPath
EOF
done
