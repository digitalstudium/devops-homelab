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
    targetRevision: 0.4.0
    chart: generic-chart
    helm:
      valuesObject:
        image:
          repository: gitlab/gitlab-ce
          tag: 18.8.2-ce.0
        resources:
          requests:
            memory: "64Mi"
            cpu: "250m"
          limits:
            memory: "3Gi"
            cpu: "2"
        ingress:
          className: traefik
          hosts:
          - host: gitlab.cluster-1.example.com
            paths:
            - path: /
              pathType: Prefix
        env:
        - name: GITLAB_OMNIBUS_CONFIG
          value: |
            external_url 'http://gitlab.cluster-1.example.com'
            puma['worker_processes'] = 0
            sidekiq['concurrency'] = 10
            prometheus_monitoring['enable'] = false
            gitlab_rails['env'] = {
              'MALLOC_CONF' => 'dirty_decay_ms:1000,muzzy_decay_ms:1000'
            }
            gitaly['configuration'] = {
              concurrency: [
                {
                  'rpc' => "/gitaly.SmartHTTPService/PostReceivePack",
                  'max_per_repo' => 3,
                }, {
                  'rpc' => "/gitaly.SSHService/SSHUploadPack",
                  'max_per_repo' => 3,
                },
              ],
              cgroups: {
                repositories: {
                  count: 2,
                },
                mountpoint: '/sys/fs/cgroup',
                hierarchy_root: 'gitaly',
                memory_bytes: 500000,
                cpu_shares: 512,
              },
            }
            gitaly['env'] = {
              'MALLOC_CONF' => 'dirty_decay_ms:1000,muzzy_decay_ms:1000',
              'GITALY_COMMAND_SPAWN_MAX_PARALLEL' => '2'
            }
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
