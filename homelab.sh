##################### CONFIGURATION #####################

export BASE_DIR=/var/talos-kvm

export CLUSTER_COUNT=2  # сколько кластеров?
export WORKERS_PER_CLUSTER=3  # сколько воркер-нод на каждый кластер?

# Внимание! По памяти и по CPU возможен overcommit, по диску - нет.

export CONTROL_PLANE_NODE_CPUS=4  # сколько CPU ядер на мастер ноде?
export CONTROL_PLANE_NODE_RAM=4096  # сколько RAM на мастер ноде?
export CONTROL_PLANE_NODE_SYSTEM_DISK=7  # сколько диска для докер образов и ephemeral storage?

export WORKER_NODE_CPUS=4  # сколько CPU ядер на каждой воркер ноде?
export WORKER_NODE_RAM=8192  # сколько RAM на каждой воркер ноде?
export WORKER_NODE_SYSTEM_DISK=15  # сколько диска для докер образов и ephemeral storage?
export WORKER_NODE_STORAGE_DISK=10 # сколько диска для PVC?

export NETWORK_NAME="talos-net"  # название сети, в которой будут находиться виртульные машины
export NETWORK_BRIDGE="talos-br0"  # название сетевого интерфейса, через который хост будет коммуницирвать с виртуальными машинами
export NETWORK="192.168.192.0"  # сеть с маской /21. Т. е. к третьему октету ещё прибавится 7. Из этой подсети будут браться адреса как для ВМ, так и для LoadBalancer

##################### CONFIGURATION #####################
# colors
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export NC='\033[0m' # No Color

./steps/01_create_clusters.sh
./steps/02_install_metallb.sh
./steps/03_install_ingress.sh
./steps/04_install_argocd.sh
./steps/05_install_spegel.sh
./steps/06_install_certmanager.sh
./steps/07_install_storage.sh
./steps/08_install_monitoring.sh
./steps/09_install_postgres_operator.sh
./steps/10_install_postgres_clusters.sh
./steps/11_install_gitlab.sh
