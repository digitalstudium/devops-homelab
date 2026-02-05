# Add color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Deploying gitlab to cluster-1 ===${NC}"
cat <<EOF | kubectl --kubeconfig=$HOME/talos-kvm/cluster-1/kubeconfig apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: gitlab
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://charts.gitlab.io
    targetRevision: 9.8.3
    chart: gitlab
    helm:
      valuesObject:
        gitlab:
          toolbox:
            enabled: false
          webservice:
            ingress:
              tls:
                secretName: gitlab-webservice-ingress-tls
            hpa:
              minReplicas: 1
              maxReplicas: 1
          gitlab-shell:
            minReplicas: 1
            maxReplicas: 1
          gitaly:
            persistence:
              size: 3Gi
          sidekiq:
            minReplicas: 1
            maxReplicas: 1
        global:
          appConfig:
            lfs:
              enabled: false
            artifacts:
              enabled: false
            uploads:
              enabled: false
            packages:
              enabled: false
          psql:
            host: postgres-cluster
            database: gitlab
            username: postgres
            password:
              secret: postgres.postgres-cluster.credentials.postgresql.acid.zalan.do
              key: password
          kas:
            enabled: false
          minio:
            enabled: false
          hosts:
            domain: cluster-1.example.com
          ingress:
            tls:
              enabled: true
              external: true
            configureCertmanager: false
            class: traefik
            annotations:
              cert-manager.io/cluster-issuer: my-ca-issuer
        installCertmanager: false
        prometheus:
          install: false
        postgresql:
          install: false
        nginx-ingress:
          enabled: false
        upgradeCheck:
          enabled: false
        registry:
          enabled: false
        redis:
          master:
            persistence:
              size: 1Gi
  destination:
    server: https://kubernetes.default.svc
    namespace: gitlab
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
      - ApplyOutOfSyncOnly=true
EOF

echo -e "${YELLOW}[gitlab] Waiting for ArgoCD sync for cluster-1${NC}"
kubectl --kubeconfig=$HOME/talos-kvm/cluster-1/kubeconfig wait --for=jsonpath='{.status.sync.status}'=Synced application/gitlab -n argocd --timeout=300s

echo -e "${GREEN}Gitlab deployed to cluster-1 successfully!${NC}"
