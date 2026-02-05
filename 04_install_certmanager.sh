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
kubectl --kubeconfig="$c" get secret -n cert-manager root-secret -o jsonpath='{.data.ca\.crt}' | base64 --decode > cluster-$CLUSTER_NUM-ca.crt
done

# import to browser, then
# sudo mv *.crt /usr/local/share/ca-certificates/
# sudo update-ca-certificates
