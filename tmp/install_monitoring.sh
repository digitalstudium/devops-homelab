#!/bin/bash

kubectl config use-context admin@cluster1

helm repo add vm https://victoriametrics.github.io/helm-charts/

cat > /tmp/vm-values.yaml << 'EOF'
server:
  enabled: true
  persistentVolume:
    enabled: false
  ingress:
    enabled: true
    hosts:
      - name: vmsingle.example.com
        path:
          - /
        port: http
    ingressClassName: traefik
EOF

helm upgrade --install vm --create-namespace \
  vm/victoria-metrics-single \
  -n monitoring \
  -f /tmp/vm-values.yaml \
  --wait

