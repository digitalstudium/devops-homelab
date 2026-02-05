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
            username: gitlab
            password:
              secret: gitlab.postgres-cluster.credentials.postgresql.acid.zalan.do
              key: password
          kas:
            enabled: false
          minio:
            enabled: false
          hosts:
            domain: gitlab.cluster-1.example.com
          ingress:
            configureCertmanager: false
            class: traefik
            annotations:
              cert-manager.io/cluster-issuer: my-ca-issuer
            tls:
              enabled: true
              secretName: gitlab-ingress-tls
        installCertmanager: false
        prometheus:
          install: false
        postgresql:
          install: false
        nginx-ingress:
          enabled: false
        upgradeCheck:
          enabled: false          
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
