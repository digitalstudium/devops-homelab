# Add color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Deploying postgres cluster to cluster-1 ===${NC}"

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

echo -e "${YELLOW}[postgresql] Waiting for StatefulSet in cluster-1...${NC}"

# Wait for the StatefulSet to exist first
timeout=60
while [ $timeout -gt 0 ]; do
  if kubectl --kubeconfig=$HOME/talos-kvm/cluster-1/kubeconfig get statefulset -n gitlab -o name | grep -q "postgres-cluster"; then
    break
  fi
  sleep 2
  timeout=$((timeout - 2))
done

kubectl --kubeconfig=$HOME/talos-kvm/cluster-1/kubeconfig wait --for=condition=ready --timeout=600s pod -l cluster-name=postgres-cluster -n gitlab

echo -e "${GREEN}Postgres cluster deployed to cluster-1 successfully!${NC}"