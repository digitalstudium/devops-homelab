cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: gitlab
  namespace: argocd
spec:
  project: default
  source:
    repoURL: http://helm.digitalstudium.com
    targetRevision: 0.3.0
    chart: generic-chart
    helm:
      valuesObject:
        image:
          repository: gitlab/gitlab-ce
          tag: 18.8.2-ce.0
        ingress:
          className: traefik
          hosts:
          - host: gitlab.example.com
            paths:
            - path: /
              pathType: Prefix	  
  destination:
    server: https://kubernetes.default.svc
    namespace: gitlab
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF

