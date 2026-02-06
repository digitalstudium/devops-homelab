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

echo -e "${YELLOW}Waiting for ArgoCD sync for cluster-$CLUSTER_NUM...${NC}"
kubectl --kubeconfig=$BASE_DIR/cluster-1/kubeconfig wait --for=jsonpath='{.status.sync.status}'=Synced application/local-path-provisioner-cluster-$CLUSTER_NUM -n argocd --timeout=300s

echo -e "${YELLOW}Waiting for local-path-provisioner deployment in cluster-$CLUSTER_NUM...${NC}"
kubectl --kubeconfig="$c" wait --for=condition=available --timeout=300s deployment/local-path-provisioner-cluster-$CLUSTER_NUM -n local-path-storage
done
