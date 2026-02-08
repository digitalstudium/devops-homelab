# Deploy to central cluster

echo -e "${BLUE}=== [victoria] Deploying to $CENTRAL_CLUSTER ===${NC}"

# Extract server URL from kubeconfig
SERVER_URL=$(grep -E '^\s*server:\s*' "$BASE_DIR/${CENTRAL_CLUSTER}/kubeconfig" | head -1 | sed 's/.*server:\s*//')

cat <<EOF | kubectl --kubeconfig=$BASE_DIR/cluster-1/kubeconfig apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: vm-$CENTRAL_CLUSTER
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://victoriametrics.github.io/helm-charts/
    targetRevision: 0.70.0
    chart: victoria-metrics-k8s-stack
    helm:
      valuesObject:
        defaultDashboards:
          enabled: false
        vmsingle:
          ingress:
            enabled: true
            annotations:
              cert-manager.io/cluster-issuer: my-ca-issuer
            ingressClassName: "traefik"
            hosts:
              - vmsingle.$CENTRAL_CLUSTER.example.com
            tls:
              - secretName: vmsingle-ingress-tls
                hosts:
                  - vmsingle.$CENTRAL_CLUSTER.example.com
          spec:
            retentionPeriod: "1d"
            storage:
              resources:
                requests:
                  storage: 1Gi
        alertmanager:
          ingress:
            enabled: true
            annotations:
              cert-manager.io/cluster-issuer: my-ca-issuer
            ingressClassName: "traefik"
            hosts:
              - alertmanager.$CENTRAL_CLUSTER.example.com
            tls:
              - secretName: alertmanager-ingress-tls
                hosts:
                  - alertmanager.$CENTRAL_CLUSTER.example.com
        vmagent:
          spec:
            externalLabels:
              cluster: $CENTRAL_CLUSTER
          ingress:
            enabled: true
            annotations:
              cert-manager.io/cluster-issuer: my-ca-issuer
            ingressClassName: "traefik"
            hosts:
              - vmagent.$CENTRAL_CLUSTER.example.com
            tls:
              - secretName: vmagent-ingress-tls
                hosts:
                  - vmagent.$CENTRAL_CLUSTER.example.com
        grafana:
          plugins:
          - victoriametrics-metrics-datasource
          sidecar:
            dashboards:
              enabled: false
          dashboardProviders:
            dashboardproviders.yaml:
              apiVersion: 1
              providers:
              - name: 'grafana-dashboards-kubernetes'
                orgId: 1
                folder: 'Kubernetes'
                type: file
                disableDeletion: true
                editable: true
                options:
                  path: /var/lib/grafana/dashboards/grafana-dashboards-kubernetes
          dashboards:
            grafana-dashboards-kubernetes:
              k8s-system-api-server:
                url: https://raw.githubusercontent.com/dotdc/grafana-dashboards-kubernetes/master/dashboards/k8s-system-api-server.json
                token: ''
              k8s-system-coredns:
                url: https://raw.githubusercontent.com/dotdc/grafana-dashboards-kubernetes/master/dashboards/k8s-system-coredns.json
                token: ''
              k8s-views-global:
                url: https://raw.githubusercontent.com/dotdc/grafana-dashboards-kubernetes/master/dashboards/k8s-views-global.json
                token: ''
              k8s-views-namespaces:
                url: https://raw.githubusercontent.com/dotdc/grafana-dashboards-kubernetes/master/dashboards/k8s-views-namespaces.json
                token: ''
              k8s-views-nodes:
                url: https://raw.githubusercontent.com/dotdc/grafana-dashboards-kubernetes/master/dashboards/k8s-views-nodes.json
                token: ''
              k8s-views-pods:
                url: https://raw.githubusercontent.com/dotdc/grafana-dashboards-kubernetes/master/dashboards/k8s-views-pods.json
                token: ''
          initChownData:
            enabled: false
          persistence:
            enabled: true
            size: 1Gi
          ingress:
            enabled: true
            annotations:
              cert-manager.io/cluster-issuer: my-ca-issuer
            ingressClassName: "traefik"
            hosts:
              - grafana.$CENTRAL_CLUSTER.example.com
            tls:
              - secretName: grafana-ingress-tls
                hosts:
                  - grafana.$CENTRAL_CLUSTER.example.com
  destination:
    server: $SERVER_URL
    namespace: monitoring
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
      - ApplyOutOfSyncOnly=true
    managedNamespaceMetadata:
      labels:
        pod-security.kubernetes.io/enforce: privileged  # for node-exporter
EOF

echo -e "${YELLOW}[victoria] Waiting for ArgoCD sync for $CENTRAL_CLUSTER...${NC}"
kubectl --kubeconfig=$BASE_DIR/cluster-1/kubeconfig wait --for=jsonpath='{.status.sync.status}'=Synced application/vm-$CENTRAL_CLUSTER -n argocd --timeout=300s

echo -e "${GREEN}Victoria stack deployed to $CENTRAL_CLUSTER successfully!${NC}"

# Deploy to remote cluster

echo -e "${BLUE}=== [victoria] Deploying to $REMOTE_CLUSTER ===${NC}"

# Extract server URL from kubeconfig
SERVER_URL=$(grep -E '^\s*server:\s*' "$BASE_DIR/${REMOTE_CLUSTER}/kubeconfig" | head -1 | sed 's/.*server:\s*//')

cat <<EOF | kubectl --kubeconfig=$BASE_DIR/cluster-1/kubeconfig apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: vm-$REMOTE_CLUSTER
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://victoriametrics.github.io/helm-charts/
    targetRevision: 0.70.0
    chart: victoria-metrics-k8s-stack
    helm:
      valuesObject:
        vmsingle:
          enabled: false
        vmalert:
          enabled: false
        alertmanager:
          enabled: false
        grafana:
          enabled: false
        vmagent:
          additionalRemoteWrites:
          - url: https://vmagent.$CENTRAL_CLUSTER.example.com/api/v1/write
          spec:
            host_aliases:
            - ip: "192.168.129.1"
              hostnames:
                - "vmagent.$CENTRAL_CLUSTER.example.com"
            secrets:
            - central-vmagetnt-tls-ca
            extraArgs:
              remoteWrite.tlsCAFile: /etc/vm/secrets/central-vmagetnt-tls-ca/$CENTRAL_CLUSTER-ca.crt
            externalLabels:
              cluster: $REMOTE_CLUSTER
          ingress:
            enabled: true
            annotations:
              cert-manager.io/cluster-issuer: my-ca-issuer
            ingressClassName: "traefik"
            hosts:
              - vmagent.$REMOTE_CLUSTER.example.com
            tls:
              - secretName: vmagent-ingress-tls
                hosts:
                  - vmagent.$REMOTE_CLUSTER.example.com
  destination:
    server: $SERVER_URL
    namespace: monitoring
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
      - ApplyOutOfSyncOnly=true
    managedNamespaceMetadata:
      labels:
        pod-security.kubernetes.io/enforce: privileged  # for node-exporter
EOF

echo -e "${YELLOW}[victoria] Waiting for ArgoCD sync for $REMOTE_CLUSTER...${NC}"
kubectl --kubeconfig=$BASE_DIR/cluster-1/kubeconfig wait --for=jsonpath='{.status.sync.status}'=Synced application/vm-$REMOTE_CLUSTER -n argocd --timeout=300s

kubectl --kubeconfig=$BASE_DIR/${REMOTE_CLUSTER}/kubeconfig -n monitoring create secret generic central-vmagetnt-tls-ca --from-file=$CENTRAL_CLUSTER-ca.crt

echo -e "${GREEN}Victoria deployed to $REMOTE_CLUSTER successfully!${NC}"
