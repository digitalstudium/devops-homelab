kubectl --kubeconfig=$HOME/talos-kvm/cluster-1/kubeconfig create ns gitlab
cat <<EOF | kubectl --kubeconfig=$HOME/talos-kvm/cluster-1/kubeconfig apply -f -
kind: "postgresql"
apiVersion: "acid.zalan.do/v1"
metadata:
  name: "postgres-cluster"
  namespace: "gitlab"
  labels:
    team: acid
spec:
  teamId: "acid"
  postgresql:
    version: "17"
  numberOfInstances: 3
  enableMasterLoadBalancer: true
  maintenanceWindows:
  volume:
    size: "1Gi"
  users:
    gitlab: []
  databases:
    gitlab: gitlab
  allowedSourceRanges:
  resources:
    requests:
      cpu: 100m
      memory: 100Mi
    limits:
      cpu: 500m
      memory: 500Mi
EOF
