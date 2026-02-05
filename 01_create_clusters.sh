#!/usr/bin/env bash
set -euo pipefail

# --- resources ---
CLUSTER_COUNT=2  # сколько кластеров?
WORKERS_PER_CLUSTER=3  # сколько воркер-нод на каждый кластер?

CONTROL_PLANE_NODE_CPUS=4  # сколько CPU ядер на каждой мастер ноде?
CONTROL_PLANE_NODE_RAM=4096  # сколько RAM на каждой мастер ноде?
CONTROL_PLANE_NODE_SYSTEM_DISK=7  # сколько диска для докер образов и ephemeral storage?

WORKER_NODE_CPUS=4  # сколько CPU ядер на каждой ворокер ноде?
WORKER_NODE_RAM=4096  # сколько RAM на каждой ворокер ноде?
WORKER_NODE_SYSTEM_DISK=13  # сколько диска для докер образов и ephemeral storage?
WORKER_NODE_STORAGE_DISK=10 # сколько диска для PVC?

ISO="metal-amd64.iso"
ISO_URL="https://github.com/siderolabs/talos/releases/latest/download/${ISO}"

# --- user/home ---
SUDO_USER=${SUDO_USER:-}
[[ $EUID -eq 0 ]] || { echo "[ERROR] Run with sudo/root"; exit 1; }
[[ -n "$SUDO_USER" ]] || { echo "[ERROR] Run via sudo from a normal user (SUDO_USER empty)"; exit 1; }
USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
BASE_DIR="${USER_HOME}/talos-kvm"

# --- network (kept compatible with your working/original script) ---
NETWORK_NAME="talos-net"
NETWORK_BRIDGE="talos-br0"
NETWORK_GATEWAY="192.168.192.1"
NETWORK_NETMASK="255.255.0.0"
DHCP_START="192.168.193.1"
DHCP_END="192.168.255.254"

# --- colors/logging ---
RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'; BLUE=$'\033[0;34m'; CYAN=$'\033[0;36m'; NC=$'\033[0m'
step(){ echo "${CYAN}[STEP]${NC} $*"; }
info(){ echo "${BLUE}[INFO]${NC} $*"; }
warn(){ echo "${YELLOW}[WARNING]${NC} $*"; }
ok(){ echo "${GREEN}[SUCCESS]${NC} $*"; }
die(){ echo "${RED}[ERROR]${NC} $*" >&2; exit 1; }

need(){ command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"; }
mb2gb(){ awk -v m="$1" 'BEGIN{printf "%.2f", m/1024}'; }

# --- cleanup on failure ---
CLEANUP_NEEDED=false
NETWORK_CREATED=false
cleanup() {
  local rc=$?
  trap - ERR INT TERM
  [[ $rc -eq 0 ]] && exit 0

  echo
  warn "Script failed/was interrupted -> cleanup"

  if [[ "$CLEANUP_NEEDED" == "true" ]]; then
    for ((c=1; c<=CLUSTER_COUNT; c++)); do
      virsh destroy "cp-$c" 2>/dev/null || true
      virsh undefine "cp-$c" --remove-all-storage 2>/dev/null || true
      for ((w=1; w<=WORKERS_PER_CLUSTER; w++)); do
        virsh destroy "worker-$c-$w" 2>/dev/null || true
        virsh undefine "worker-$c-$w" --remove-all-storage 2>/dev/null || true
      done
    done
  fi

  if [[ "$NETWORK_CREATED" == "true" ]]; then
    virsh net-destroy "$NETWORK_NAME" 2>/dev/null || true
    virsh net-undefine "$NETWORK_NAME" 2>/dev/null || true
    # remove leftover bridge (common cause of "net-start" problems next run)
    if ip link show "$NETWORK_BRIDGE" >/dev/null 2>&1; then
      ip link set "$NETWORK_BRIDGE" down 2>/dev/null || true
      ip link delete "$NETWORK_BRIDGE" type bridge 2>/dev/null || true
    fi
  fi

  exit "$rc"
}
trap cleanup ERR INT TERM

# --- permissions: allow libvirt-qemu to read BASE_DIR in home ---
setup_permissions() {
  step "Setting up permissions for: $BASE_DIR"
  mkdir -p "$BASE_DIR"
  chown "$SUDO_USER:$SUDO_USER" "$BASE_DIR"
  chmod 755 "$BASE_DIR"

  local libvirt_user="libvirt-qemu"
  getent passwd libvirt-qemu >/dev/null 2>&1 || libvirt_user="qemu"

  if command -v setfacl >/dev/null 2>&1; then
    setfacl -m "u:${libvirt_user}:rx" "$BASE_DIR" || true
    setfacl -m "u:${libvirt_user}:rx" "$USER_HOME" || true
    info "ACL set for ${libvirt_user}"
  else
    warn "setfacl not found; falling back to chmod o+rx on $BASE_DIR and $USER_HOME"
    chmod o+rx "$BASE_DIR" || true
    chmod o+rx "$USER_HOME" || true
  fi
}

# --- resource check + summary (updated for worker-only storage disks) ---
check_resources() {
  step "Checking system resources..."
  echo "Base directory: $BASE_DIR"
  echo

  local total_cpu total_ram total_disk
  total_cpu=$(( (CONTROL_PLANE_NODE_CPUS + WORKER_NODE_CPUS * WORKERS_PER_CLUSTER) * CLUSTER_COUNT ))
  total_ram=$(( (CONTROL_PLANE_NODE_RAM + WORKER_NODE_RAM * WORKERS_PER_CLUSTER) * CLUSTER_COUNT ))     # MB
  # Only workers get storage disks, control planes don't
  total_disk=$(( (CONTROL_PLANE_NODE_SYSTEM_DISK * CLUSTER_COUNT) + ((WORKER_NODE_SYSTEM_DISK + WORKER_NODE_STORAGE_DISK) * WORKERS_PER_CLUSTER * CLUSTER_COUNT) ))

  local avail_cpu avail_ram avail_disk
  avail_cpu=$(nproc)
  avail_ram=$(free -m | awk '/^Mem:/{print $2}')
  avail_disk=$(df -BG "$BASE_DIR" 2>/dev/null | awk 'NR==2{gsub(/G/,"",$4);print $4}')
  [[ -n "${avail_disk:-}" ]] || avail_disk=$(df -BG "$USER_HOME" | awk 'NR==2{gsub(/G/,"",$4);print $4}')

  info "=== PLAN ==="
  info "Clusters: $CLUSTER_COUNT | Workers/cluster: $WORKERS_PER_CLUSTER"
  info "Per control plane node: ${CONTROL_PLANE_NODE_CPUS} vCPU, $(mb2gb "$CONTROL_PLANE_NODE_RAM")GB RAM, ${CONTROL_PLANE_NODE_SYSTEM_DISK}GB system disk"
  info "Per worker node : ${WORKER_NODE_CPUS} vCPU, $(mb2gb "$WORKER_NODE_RAM")GB RAM, ${WORKER_NODE_SYSTEM_DISK}GB system disk + ${WORKER_NODE_STORAGE_DISK}GB storage disk"
  info "=== TOTAL REQUESTED ==="
  info "CPU:  $total_cpu vCPU"
  info "RAM:  $(mb2gb "$total_ram")GB"
  info "Disk: $total_disk GB"
  info "=== AVAILABLE ==="
  info "CPU cores: $avail_cpu"
  info "RAM:       $(mb2gb "$avail_ram")GB"
  info "Disk free: $avail_disk GB (checked at $BASE_DIR)"
  echo

  (( total_cpu > avail_cpu )) && warn "CPU overcommit: requested $total_cpu vCPU > $avail_cpu cores"
  (( total_ram > avail_ram )) && warn "RAM overcommit: requested $(mb2gb "$total_ram")GB > available $(mb2gb "$avail_ram")GB"
  (( total_disk <= avail_disk )) || die "Insufficient disk: need ${total_disk}GB free, have ${avail_disk}GB"

  [[ -e /dev/kvm ]] || die "KVM not available (/dev/kvm missing)"
  systemctl is-active --quiet libvirtd || die "libvirtd is not running"

  ok "Resource check passed"
}

# --- network: MUST remove if it exists (and delete leftover bridge) ---
recreate_network() {
  step "Recreating libvirt network: $NETWORK_NAME (will remove existing one if present)"

  if virsh net-info "$NETWORK_NAME" >/dev/null 2>&1; then
    info "Destroy/undefine existing network '$NETWORK_NAME'"
    virsh net-destroy "$NETWORK_NAME" 2>/dev/null || true
    virsh net-undefine "$NETWORK_NAME" 2>/dev/null || true
  fi

  # critical: bridge device can remain and break next net-start
  if ip link show "$NETWORK_BRIDGE" >/dev/null 2>&1; then
    info "Removing leftover bridge '$NETWORK_BRIDGE'"
    ip link set "$NETWORK_BRIDGE" down 2>/dev/null || true
    ip link delete "$NETWORK_BRIDGE" type bridge 2>/dev/null || true
  fi

  local xml="$BASE_DIR/network.xml"
  cat > "$xml" <<EOF
<network>
  <name>$NETWORK_NAME</name>
  <bridge name="$NETWORK_BRIDGE" stp="off" delay="0"/>
  <forward mode="nat">
    <nat><port start="1024" end="65535"/></nat>
  </forward>
  <ip address="$NETWORK_GATEWAY" netmask="$NETWORK_NETMASK">
    <dhcp><range start="$DHCP_START" end="$DHCP_END"/></dhcp>
  </ip>
</network>
EOF

  virsh net-define "$xml"
  virsh net-start "$NETWORK_NAME"
  virsh net-autostart "$NETWORK_NAME"
  NETWORK_CREATED=true
  ok "Network active: $NETWORK_NAME (bridge=$NETWORK_BRIDGE, gw=$NETWORK_GATEWAY, dhcp=$DHCP_START-$DHCP_END)"

  # wait for dnsmasq lease infra to appear (prevents “hang” later)
  for _ in {1..20}; do
    [[ -r "/var/lib/libvirt/dnsmasq/${NETWORK_NAME}.leases" ]] && break
    sleep 1
  done
}

# --- IP discovery: verbose + uses domifaddr first (like Talos docs) ---
get_vm_ip() {
  local vm="$1" tries="${2:-60}" i ip mac
  local leases="/var/lib/libvirt/dnsmasq/${NETWORK_NAME}.leases"

  for ((i=1; i<=tries; i++)); do
    # Source "lease" is the most reliable for NAT networks; "arp" can help sometimes.
    ip=$(virsh domifaddr "$vm" --source lease 2>/dev/null | awk '/ipv4/ {print $4; exit}' | cut -d/ -f1 || true)
    [[ -n "${ip:-}" && ! "$ip" =~ ^127\. ]] && { echo "$ip"; return 0; }

    ip=$(virsh domifaddr "$vm" --source arp 2>/dev/null | awk '/ipv4/ {print $4; exit}' | cut -d/ -f1 || true)
    [[ -n "${ip:-}" && ! "$ip" =~ ^127\. ]] && { echo "$ip"; return 0; }

    # Fallback: read dnsmasq leases by MAC
    if [[ -r "$leases" ]]; then
      mac=${mac:-$(virsh domiflist "$vm" 2>/dev/null | awk -v n="$NETWORK_NAME" '$3==n {print tolower($5); exit}')}
      if [[ -n "${mac:-}" ]]; then
        ip=$(awk -v m="$mac" 'tolower($2)==m {print $3; exit}' "$leases" 2>/dev/null || true)
        [[ -n "${ip:-}" && ! "$ip" =~ ^127\. ]] && { echo "$ip"; return 0; }
      fi
    fi
    sleep 5
  done
  return 1
}

retry() {
  local max="${1:-30}" sleep_s="${2:-10}"; shift 2
  local i
  for ((i=1; i<=max; i++)); do
    "$@" && return 0
    info "Retry $i/$max: $*"
    sleep "$sleep_s"
  done
  return 1
}

apply_config() {
  local ip="$1" file="$2"
  retry 30 10 sudo -u "$SUDO_USER" talosctl apply-config --insecure --nodes "$ip" --file "$file" >/dev/null
}

# --- Updated VM creation functions ---
make_controlplane_vm() {
  local name="$1" ram="$2" cpu="$3" system_disk="$4" size="$5"

  step "Creating Control Plane VM: $name (cpu=$cpu ram=${ram}MB system disk=${size}G)"
  [[ -f "$system_disk" ]] || sudo -u "$SUDO_USER" qemu-img create -f qcow2 "$system_disk" "${size}G" >/dev/null
  chown "$SUDO_USER:$SUDO_USER" "$system_disk" 2>/dev/null || true
  chmod 644 "$system_disk" 2>/dev/null || true

  virt-install \
    --virt-type kvm \
    --name "$name" \
    --ram "$ram" \
    --vcpus "$cpu" \
    --disk "path=$system_disk,bus=virtio,size=$size,format=qcow2" \
    --cdrom "$BASE_DIR/$ISO" \
    --os-variant=linux2022 \
    --network "network=$NETWORK_NAME" \
    --graphics none \
    --noautoconsole \
    --boot hd,cdrom \
    --autostart

  ok "Control Plane VM created: $name"
}

make_worker_vm() {
  local name="$1" ram="$2" cpu="$3" system_disk="$4" size="$5"

  step "Creating Worker VM: $name (cpu=$cpu ram=${ram}MB system disk=${size}G + storage disk: ${WORKER_NODE_STORAGE_DISK}G)"

  # Create OS disk
  [[ -f "$system_disk" ]] || sudo -u "$SUDO_USER" qemu-img create -f qcow2 "$system_disk" "${size}G" >/dev/null
  chown "$SUDO_USER:$SUDO_USER" "$system_disk" 2>/dev/null || true
  chmod 644 "$system_disk" 2>/dev/null || true

  # Create storage disk disk (only for workers)
  local storage_disk="${system_disk%.*}-storage.qcow2"
  sudo -u "$SUDO_USER" qemu-img create -f qcow2 "$storage_disk" "${WORKER_NODE_STORAGE_DISK}G" >/dev/null
  chown "$SUDO_USER:$SUDO_USER" "$storage_disk" 2>/dev/null || true
  chmod 644 "$storage_disk" 2>/dev/null || true

  virt-install \
    --virt-type kvm \
    --name "$name" \
    --ram "$ram" \
    --vcpus "$cpu" \
    --disk "path=$system_disk,bus=virtio,size=$size,format=qcow2" \
    --disk "path=$storage_disk,bus=virtio,size=$WORKER_NODE_STORAGE_DISK,format=qcow2" \
    --cdrom "$BASE_DIR/$ISO" \
    --os-variant=linux2022 \
    --network "network=$NETWORK_NAME" \
    --graphics none \
    --noautoconsole \
    --boot hd,cdrom \
    --autostart

  ok "Worker VM created: $name"
}

# --- health check ---
check_cluster_health() {
  local cluster_num="$1" cp_ip="$2" config_file
  step "Checking health of cluster-$cluster_num (control plane: $cp_ip)"

  config_file="$BASE_DIR/cluster-$cluster_num/configs/talosconfig"

  # Run the health check command exactly as you showed
  sudo -u "$SUDO_USER" env TALOSCONFIG="$config_file" \
    talosctl health -c "cluster-$cluster_num" -n "$cp_ip"
}

main() {
  step "Checking prerequisites..."
  need virsh; need virt-install; need qemu-img; need curl; need talosctl; need awk; need df; need free
  ok "Prerequisites OK"

  setup_permissions
  check_resources

  read -r -p "Proceed? (type yes/no): " confirm
  [[ "$confirm" == "yes" ]] || die "Cancelled"

  step "Preparing working directory..."
  mkdir -p "$BASE_DIR"
  chown "$SUDO_USER:$SUDO_USER" "$BASE_DIR" || true
  cd "$BASE_DIR"

  step "Ensuring Talos ISO exists..."
  if [[ ! -f "$ISO" ]]; then
    info "Downloading $ISO_URL"
    sudo -u "$SUDO_USER" curl --fail --progress-bar -L "$ISO_URL" -o "$ISO"
    ok "ISO downloaded: $BASE_DIR/$ISO"
  else
    ok "ISO already exists: $BASE_DIR/$ISO"
  fi
  chown "$SUDO_USER:$SUDO_USER" "$ISO" 2>/dev/null || true
  chmod 644 "$ISO" 2>/dev/null || true

  CLEANUP_NEEDED=true

  recreate_network

  step "Creating VMs..."
  for ((c=1; c<=CLUSTER_COUNT; c++)); do
    step "Cluster $c: directories"
    mkdir -p "$BASE_DIR/cluster-$c/configs"
    chown -R "$SUDO_USER:$SUDO_USER" "$BASE_DIR/cluster-$c" || true
    chmod 755 "$BASE_DIR/cluster-$c" "$BASE_DIR/cluster-$c/configs" 2>/dev/null || true

    # Control plane (NO storage disk)
    make_controlplane_vm "cp-$c" "$CONTROL_PLANE_NODE_RAM" "$CONTROL_PLANE_NODE_CPUS" "$BASE_DIR/cluster-$c/cp-disk.qcow2" "$CONTROL_PLANE_NODE_SYSTEM_DISK"

    # Workers (WITH storage disk)
    for ((w=1; w<=WORKERS_PER_CLUSTER; w++)); do
      make_worker_vm "worker-$c-$w" "$WORKER_NODE_RAM" "$WORKER_NODE_CPUS" "$BASE_DIR/cluster-$c/worker-$w-disk.qcow2" "$WORKER_NODE_SYSTEM_DISK"
    done
  done
  ok "All VMs defined and started"
  info "Currently running VMs:"
  virsh list || true

  step "Waiting for VMs to boot and get IPs..."

  declare -A CP_IPS WORKER_IPS

  for ((c=1; c<=CLUSTER_COUNT; c++)); do
    step "Cluster $c: discovering node IPs"
    local cp_ip
    cp_ip=$(get_vm_ip "cp-$c" 60) || die "Failed to get IP for cp-$c (check: virsh net-dhcp-leases $NETWORK_NAME)"
    ok "cp-$c IP: $cp_ip"
    CP_IPS["$c"]="$cp_ip"

    worker_list=()
    for ((w=1; w<=WORKERS_PER_CLUSTER; w++)); do
      if ip=$(get_vm_ip "worker-$c-$w" 60); then
        ok "worker-$c-$w IP: $ip"
        worker_list+=("$ip")
      else
        warn "Failed to get IP for worker-$c-$w"
      fi
    done
    WORKER_IPS["$c"]="${worker_list[*]}"

    step "Cluster $c: generating Talos config"
    cfgdir="$BASE_DIR/cluster-$c/configs"
    sudo -u "$SUDO_USER" talosctl gen config "cluster-$c" "https://${cp_ip}:6443" \
      --install-disk /dev/vda -o "$cfgdir" >/dev/null
    ok "Config generated: $cfgdir"

    step "Cluster $c: applying config (controlplane)"
    apply_config "$cp_ip" "$cfgdir/controlplane.yaml"
    ok "Controlplane configured"

    step "Cluster $c: applying config (workers)"
    for ip in ${WORKER_IPS["$c"]}; do
      # After generating configs, modify worker.yaml
      step "Cluster $c: adding storage to worker config of $ip"
      cat > patch.yaml <<EOF
machine:
  disks:
    - device: /dev/vdb
      partitions:
        - mountpoint: /var/mnt/local-path-provisioner # for PVC
  files:
    - path: /etc/cri/conf.d/20-customization.part # for spegel https://spegel.dev/
      op: create
      content: |
        [plugins."io.containerd.cri.v1.images"]
          discard_unpacked_layers = false
EOF
      talosctl machineconfig patch $cfgdir/worker.yaml --patch @patch.yaml -o $cfgdir/worker-with-storage.yaml
      worker_config=$cfgdir/worker-with-storage.yaml

      # Then apply the merged config
      apply_config "$ip" "$worker_config" || warn "Worker config failed for $ip"
    done

    step "Cluster $c: bootstrap + kubeconfig"
    talosconfig="$cfgdir/talosconfig"
    sudo -u "$SUDO_USER" env TALOSCONFIG="$talosconfig" talosctl config endpoint "$cp_ip" >/dev/null
    sudo -u "$SUDO_USER" env TALOSCONFIG="$talosconfig" talosctl config node "$cp_ip" >/dev/null
    echo "[INFO] Waiting for $cp_ip:50000 to open..."
    opened=false
    for i in {1..120}; do
      if timeout 1 bash -c "</dev/tcp/$cp_ip/50000" >/dev/null 2>&1; then
        echo "[SUCCESS] Port 50000 is open on $cp_ip" >&2
        opened=true
        break
      fi
      echo "[INFO] Waiting for $cp_ip:50000 ($i/120)" >&2
      sleep 5
    done

    $opened || die "Talos API never opened on $cp_ip"
    retry 30 10 sudo -u "$SUDO_USER" env TALOSCONFIG="$talosconfig" talosctl -n "$cp_ip" bootstrap >/dev/null
    ok "Cluster $c bootstrapped"

    retry 30 10 sudo -u "$SUDO_USER" env TALOSCONFIG="$talosconfig" talosctl -n "$cp_ip" kubeconfig "$BASE_DIR/cluster-$c/kubeconfig" >/dev/null \
      && ok "Kubeconfig: $BASE_DIR/cluster-$c/kubeconfig" \
      || warn "Failed to fetch kubeconfig for cluster $c"
  done

  for ((c=1; c<=CLUSTER_COUNT; c++)); do
    if [[ -v "CP_IPS[$c]" ]]; then
    check_cluster_health "$c" "${CP_IPS[$c]}"
    fi
  done

  CLEANUP_NEEDED=false
  trap - ERR INT TERM

  echo
  ok "CREATION COMPLETE"
  info "Network: $NETWORK_NAME"
  info "Base dir: $BASE_DIR"
  info "Worker storage disks: ${WORKER_NODE_STORAGE_DISK}GB each"
  echo "=== Cluster IPs ==="
  for ((c=1; c<=CLUSTER_COUNT; c++)); do
    echo "Cluster $c:"
    echo "  Control plane: ${CP_IPS[$c]}"
    echo "  Workers:       ${WORKER_IPS[$c]:-(none)}"
    echo "  Kubeconfig:    $BASE_DIR/cluster-$c/kubeconfig"
  done
}

main
