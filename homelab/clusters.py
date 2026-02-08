#!/usr/bin/env python3
import os
import shutil
import signal
import socket
import sys
import tempfile
import time
from pathlib import Path
from typing import List, Optional, Tuple

from homelab.utils import commands, config, logger

# constants
NETWORK_NETMASK = "255.255.248.0"
ISO_NAME = "metal-amd64.iso"
ISO_URL = f"https://github.com/siderolabs/talos/releases/latest/download/{ISO_NAME}"


# global state
CONFIG = None
sudo_user = None
base_dir = None
network_gateway = None
dhcp_start = None
dhcp_end = None


def need(cmd: str):
    """Check if command exists"""
    if shutil.which(cmd) is None:
        logger.die(f"Missing required command: {cmd}")


def mb2gb(mb: int) -> float:
    """Convert MB to GB"""
    return mb / 1024


def get_network_gateway(config_data):
    subnet = config_data.virtual_network.subnet
    o1, o2, o3, _ = subnet.split(".")
    return f"{o1}.{o2}.{o3}.1"


def get_dhcp_start(config_data):
    subnet = config_data.virtual_network.subnet
    o1, o2, o3, _ = subnet.split(".")
    return f"{o1}.{o2}.{o3}.2"


def get_dhcp_end(config_data):
    subnet = config_data.virtual_network.subnet
    o1, o2, o3, _ = subnet.split(".")
    return f"{o1}.{o2}.{o3}.254"


def create_qemu_disk(size: int, disk_path: str):
    """Create a disk image"""
    commands.run(
        [
            "qemu-img",
            "create",
            "-f",
            "qcow2",
            str(disk_path),
            f"{size}G",
        ]
    )


def require_sudo():
    if os.geteuid() != 0:
        logger.die("Run with sudo!")


def setup_sudo_user():
    global sudo_user
    sudo_user = os.environ.get("SUDO_USER")
    if not sudo_user:
        logger.die("Run via sudo from a normal user (SUDO_USER empty)")


def setup_environment():
    """Setup environment variables and permissions"""
    global base_dir, network_gateway, dhcp_start, dhcp_end

    logger.step("Setting up environment")
    setup_sudo_user()

    base_dir = Path(CONFIG.base_dir)
    network_gateway = get_network_gateway(CONFIG)
    dhcp_start = get_dhcp_start(CONFIG)
    dhcp_end = get_dhcp_end(CONFIG)

    logger.info(f"Base directory: {base_dir}")
    logger.info(f"User: {sudo_user}")


def signal_handler(signum, frame):
    """Handle signals for cleanup"""
    print("\n")
    logger.warn("Script interrupted -> cleanup, please wait for a while...")
    cleanup()
    sys.exit(1)


def get_all_vm_names() -> set[str]:
    """Get set of all defined VM names."""
    result = commands.run(["virsh", "list", "--all", "--name"], check=False)
    if result.returncode != 0:
        return set()
    return {name.strip() for name in result.stdout.splitlines() if name.strip()}


def destroy_vm(vm_name: str, existing_vms: set[str]):
    """Destroy and undefine a single VM with its storage."""
    if vm_name not in existing_vms:
        logger.info(f"  {vm_name} — already absent, skipping")
        return

    logger.info(f"  {vm_name} — removing...")
    commands.run(["virsh", "destroy", vm_name], check=False)
    commands.run(["virsh", "undefine", vm_name, "--remove-all-storage"], check=False)
    logger.ok(f"  {vm_name} removed")


def cleanup_control_plane_nodes(existing_vms: set[str]):
    """Cleanup all control plane VMs."""
    logger.step("Removing control plane VMs")
    for c in range(1, CONFIG.cluster_count + 1):
        destroy_vm(f"cp-{c}", existing_vms)


def cleanup_worker_nodes(existing_vms: set[str]):
    """Cleanup all worker VMs."""
    logger.step("Removing worker VMs")
    for c in range(1, CONFIG.cluster_count + 1):
        for w in range(1, CONFIG.workers_per_cluster + 1):
            destroy_vm(f"worker-{c}-{w}", existing_vms)


def remove_virtual_network():
    """Remove the virtual network if it exists."""
    logger.step(f"Removing network: {CONFIG.virtual_network.name}")

    # Check if network exists first
    result = commands.run(
        ["virsh", "net-info", CONFIG.virtual_network.name], check=False
    )
    if result.returncode != 0:
        logger.info("  Network not found, skipping")
        return

    commands.run(["virsh", "net-destroy", CONFIG.virtual_network.name], check=False)
    commands.run(["virsh", "net-undefine", CONFIG.virtual_network.name], check=False)
    logger.ok(f"  Network {CONFIG.virtual_network.name} removed")


def remove_leftover_bridge():
    """Remove leftover bridge interface if it exists."""
    if not check_bridge_exists():
        return

    logger.info(f"  Removing leftover bridge: {CONFIG.virtual_network.bridge}")
    commands.run(
        ["ip", "link", "set", CONFIG.virtual_network.bridge, "down"], check=False
    )
    commands.run(
        ["ip", "link", "delete", CONFIG.virtual_network.bridge, "type", "bridge"],
        check=False,
    )


def check_bridge_exists() -> bool:
    """Check if network bridge exists"""
    result = commands.run(
        ["ip", "link", "show", CONFIG.virtual_network.bridge], check=False
    )
    return result.returncode == 0


def cleanup(force: bool = False):
    """Cleanup resources."""
    print_cleanup_warning()

    if not force:
        confirm = input("Type 'yes' to proceed: ").strip()
        if confirm != "yes":
            logger.info("Cleanup cancelled")
            return

    global CONFIG, base_dir
    if CONFIG is None:
        try:
            CONFIG = config.load()
        except Exception as e:
            logger.warn(f"Could not load config: {e}")

    base_dir = Path(CONFIG.base_dir) if CONFIG else None

    # Get VM list ONCE
    existing_vms = get_all_vm_names()

    if CONFIG is not None:
        cleanup_control_plane_nodes(existing_vms)
        cleanup_worker_nodes(existing_vms)
        remove_virtual_network()
    else:
        cleanup_all_vms_by_pattern()
        remove_network_by_default_name()

    remove_leftover_bridge()
    if base_dir:
        cleanup_data_directories()

    logger.ok("Cleanup complete!")


def print_cleanup_warning():
    """Print destructive operation warning banner."""
    print()
    print("=" * 60)
    print("⚠️   WARNING: DESTRUCTIVE OPERATION")
    print("=" * 60)
    print("This will destroy ALL VMs, networks, and data associated with:")
    print("  - All control plane VMs (cp-*)")
    print("  - All worker VMs (worker-*)")
    print("  - Virtual network and bridge")
    print("  - All disk images and configuration files")
    print()
    print("This operation is IRREVERSIBLE!")
    print("=" * 60)
    print()


def cleanup_data_directories():
    """Cleanup data directories."""
    logger.info("Cleaning up data directories...")

    # Remove cluster directories
    if base_dir.exists():
        for item in base_dir.glob("cluster-*"):
            if item.is_dir():
                logger.info(f"  Removing directory: {item}")
                shutil.rmtree(item, ignore_errors=True)


def cleanup_all_vms_by_pattern():
    """Cleanup VMs by common naming patterns when CONFIG is not available."""
    logger.info("Cleaning up VMs by pattern matching")

    # Try to find and destroy VMs with common patterns
    patterns = ["cp-", "worker-"]

    # Get list of all VMs
    result = commands.run(["virsh", "list", "--all"], capture_output=True, check=False)
    if result.returncode == 0:
        for line in result.stdout.splitlines()[2:]:  # Skip header
            if line.strip():
                vm_name = line.split()[1]
                if any(pattern in vm_name for pattern in patterns):
                    destroy_vm(vm_name)


def remove_network_by_default_name():
    """Remove network by common default names."""
    default_networks = ["talos-network", "taloslab", "kube-net"]

    for net_name in default_networks:
        result = commands.run(["virsh", "net-info", net_name], check=False)
        if result.returncode == 0:
            logger.info(f"Removing network: {net_name}")
            commands.run(["virsh", "net-destroy", net_name], check=False)
            commands.run(["virsh", "net-undefine", net_name], check=False)


def setup_permissions():
    """Setup permissions for directories"""
    logger.step("Setting up permissions")

    # Create base directory
    base_dir.mkdir(parents=True, exist_ok=True)

    # Set ownership
    shutil.chown(base_dir, sudo_user, sudo_user)
    base_dir.chmod(0o755)

    # Determine libvirt user
    libvirt_user = "libvirt-qemu"
    try:
        import pwd

        pwd.getpwnam(libvirt_user)
    except KeyError:
        libvirt_user = "qemu"

    # Set ACLs if available
    if shutil.which("setfacl"):
        commands.run(
            ["setfacl", "-m", f"u:{libvirt_user}:rx", str(base_dir)],
            check=False,
        )
        logger.info(f"ACL set for {libvirt_user}")
    else:
        logger.warn("setfacl not found; falling back to chmod")
        base_dir.chmod(0o755)

    logger.ok("Permissions set")


def calculate_required_resources():
    """Calculate total required resources."""
    cp = CONFIG.control_plane_node
    worker = CONFIG.worker_node

    total_cpu = (
        cp.cpus + worker.cpus * CONFIG.workers_per_cluster
    ) * CONFIG.cluster_count
    total_ram = (
        cp.ram + worker.ram * CONFIG.workers_per_cluster
    ) * CONFIG.cluster_count  # MB
    total_disk = (cp.system_disk * CONFIG.cluster_count) + (
        (worker.system_disk + worker.storage_disk)
        * CONFIG.workers_per_cluster
        * CONFIG.cluster_count
    )

    return total_cpu, total_ram, total_disk


def get_available_cpu():
    """Get available CPU cores."""
    return os.cpu_count()


def get_available_ram():
    """Get available RAM in MB."""
    with open("/proc/meminfo", "r") as f:
        for line in f:
            if line.startswith("MemTotal:"):
                return int(line.split()[1]) // 1024  # Convert kB to MB
    return 0


def get_available_disk():
    """Get available disk space in GB."""
    stat = shutil.disk_usage(base_dir)
    return stat.free // (1024**3)  # Convert to GB


def log_resource_plan(cp, worker, total_cpu, total_ram, total_disk):
    """Log the resource allocation plan."""
    logger.info("=== PLAN ===")
    logger.info(
        f"Clusters: {CONFIG.cluster_count} | Workers/cluster: {CONFIG.workers_per_cluster}"
    )
    logger.info(
        f"Per control plane node: {cp.cpus} vCPU, {mb2gb(cp.ram):.2f}GB RAM, {cp.system_disk}GB system disk"
    )
    logger.info(
        f"Per worker node: {worker.cpus} vCPU, {mb2gb(worker.ram):.2f}GB RAM, {worker.system_disk}GB system disk + {worker.storage_disk}GB storage disk"
    )
    logger.info("=== TOTAL REQUESTED ===")
    logger.info(f"CPU:  {total_cpu} vCPU")
    logger.info(f"RAM:  {mb2gb(total_ram):.2f}GB")
    logger.info(f"Disk: {total_disk} GB")


def log_available_resources(avail_cpu, avail_ram, avail_disk):
    """Log available system resources."""
    logger.info("=== AVAILABLE ===")
    logger.info(f"CPU cores: {avail_cpu}")
    logger.info(f"RAM:       {mb2gb(avail_ram):.2f}GB")
    logger.info(f"Disk free: {avail_disk} GB (checked at {base_dir})")
    print()


def check_cpu_overcommit(total_cpu, avail_cpu):
    """Check if CPU requested exceeds available."""
    if total_cpu > avail_cpu:
        logger.warn(f"CPU overcommit: requested {total_cpu} vCPU > {avail_cpu} cores")


def check_ram_overcommit(total_ram, avail_ram):
    """Check if RAM requested exceeds available."""
    if total_ram > avail_ram:
        logger.warn(
            f"RAM overcommit: requested {mb2gb(total_ram):.2f}GB > available {mb2gb(avail_ram):.2f}GB"
        )


def check_disk_space(total_disk, avail_disk):
    """Check if disk space requested exceeds available."""
    if total_disk > avail_disk:
        logger.die(f"Insufficient disk: need {total_disk}GB free, have {avail_disk}GB")


def check_kvm_available():
    """Check if KVM is available."""
    if not Path("/dev/kvm").exists():
        logger.die("KVM not available (/dev/kvm missing)")


def check_libvirtd_running():
    """Check if libvirtd service is running."""
    result = commands.run(["systemctl", "is-active", "libvirtd"], check=False)
    if result.returncode != 0:
        logger.die("libvirtd is not running")


def check_resources():
    """Check system resources - main aggregator function."""
    logger.step("Checking system resources")

    cp = CONFIG.control_plane_node
    worker = CONFIG.worker_node

    # Calculate required resources
    total_cpu, total_ram, total_disk = calculate_required_resources()

    # Get available resources
    avail_cpu = get_available_cpu()
    avail_ram = get_available_ram()
    avail_disk = get_available_disk()

    # Log resource information
    log_resource_plan(cp, worker, total_cpu, total_ram, total_disk)
    log_available_resources(avail_cpu, avail_ram, avail_disk)

    # Check for overcommit
    check_cpu_overcommit(total_cpu, avail_cpu)
    check_ram_overcommit(total_ram, avail_ram)
    check_disk_space(total_disk, avail_disk)

    # Check virtualization prerequisites
    check_kvm_available()
    check_libvirtd_running()

    logger.ok("Resource check passed")


def remove_existing_network():
    """Remove existing libvirt network if it exists."""
    result = commands.run(
        ["virsh", "net-info", CONFIG.virtual_network.name], check=False
    )
    if result.returncode == 0:
        logger.info(
            f"Destroy/undefine existing network '{CONFIG.virtual_network.name}'"
        )
        commands.run(["virsh", "net-destroy", CONFIG.virtual_network.name], check=False)
        commands.run(
            ["virsh", "net-undefine", CONFIG.virtual_network.name], check=False
        )


def create_network_xml():
    """Create XML configuration for the libvirt network."""
    network_xml = f"""<network>
  <name>{CONFIG.virtual_network.name}</name>
  <bridge name="{CONFIG.virtual_network.bridge}" stp="off" delay="0"/>
  <forward mode="nat">
    <nat><port start="1024" end="65535"/></nat>
  </forward>
  <ip address="{network_gateway}" netmask="{NETWORK_NETMASK}">
    <dhcp><range start="{dhcp_start}" end="{dhcp_end}"/></dhcp>
  </ip>
</network>"""
    return network_xml


def write_xml_to_temp_file(xml_content):
    """Write XML content to a temporary file."""
    with tempfile.NamedTemporaryFile(mode="w", suffix=".xml", delete=False) as f:
        f.write(xml_content)
        return f.name


def define_and_start_network(xml_file):
    """Define and start the libvirt network."""
    commands.run(["virsh", "net-define", xml_file])
    commands.run(["virsh", "net-start", CONFIG.virtual_network.name])
    commands.run(["virsh", "net-autostart", CONFIG.virtual_network.name])


def wait_for_dnsmasq_lease_file():
    """Wait for dnsmasq lease file to be created."""
    lease_file = Path(f"/var/lib/libvirt/dnsmasq/{CONFIG.virtual_network.name}.leases")
    for _ in range(20):
        if lease_file.exists():
            break
        time.sleep(1)


def log_network_creation_success():
    """Log successful network creation."""
    logger.ok(
        f"Network active: {CONFIG.virtual_network.name} (bridge={CONFIG.virtual_network.bridge}, gw={network_gateway}, dhcp={dhcp_start}-{dhcp_end})"
    )


def cleanup_temp_file(xml_file):
    """Clean up temporary XML file."""
    Path(xml_file).unlink(missing_ok=True)


def recreate_network():
    """Recreate libvirt network - main aggregator function."""
    logger.step(f"Recreating libvirt network: {CONFIG.virtual_network.name}")

    remove_existing_network()

    if check_bridge_exists():
        logger.info(f"Removing leftover bridge '{CONFIG.virtual_network.bridge}'")
        remove_leftover_bridge()  # Reuse from earlier refactoring

    network_xml = create_network_xml()
    xml_file = write_xml_to_temp_file(network_xml)

    try:
        define_and_start_network(xml_file)
        log_network_creation_success()
        wait_for_dnsmasq_lease_file()
    finally:
        cleanup_temp_file(xml_file)


def parse_ip_from_domifaddr_output(output: str) -> Optional[str]:
    """Parse IP address from virsh domifaddr output."""
    for line in output.splitlines():
        if "ipv4" in line:
            parts = line.split()
            if len(parts) >= 4:
                ip = parts[3].split("/")[0]
                if ip and not ip.startswith("127."):
                    return ip
    return None


def get_vm_ip_from_source(vm_name: str, source: str) -> Optional[str]:
    """Get VM IP address using a specific source (lease or arp)."""
    result = commands.run(
        ["virsh", "domifaddr", vm_name, "--source", source], check=False
    )
    if result.returncode == 0:
        return parse_ip_from_domifaddr_output(result.stdout)
    return None


def get_vm_mac_address(vm_name: str) -> Optional[str]:
    """Get MAC address of VM's interface on the virtual network."""
    result = commands.run(["virsh", "domiflist", vm_name], check=False)
    if result.returncode == 0:
        for line in result.stdout.splitlines():
            if CONFIG.virtual_network.name in line:
                parts = line.split()
                if len(parts) >= 5:
                    return parts[4].lower()
    return None


def get_ip_from_dnsmasq_leases(mac_address: str) -> Optional[str]:
    """Find IP address in dnsmasq leases file by MAC address."""
    lease_file = Path(f"/var/lib/libvirt/dnsmasq/{CONFIG.virtual_network.name}.leases")

    if not lease_file.exists():
        return None

    with open(lease_file, "r") as f:
        for lease_line in f:
            parts = lease_line.split()
            if len(parts) >= 3 and parts[1].lower() == mac_address:
                ip = parts[2]
                if ip and not ip.startswith("127."):
                    return ip
    return None


def try_get_vm_ip_lease_source(vm_name: str) -> Optional[str]:
    return get_vm_ip_from_source(vm_name, "lease")


def try_get_vm_ip_arp_source(vm_name: str) -> Optional[str]:
    return get_vm_ip_from_source(vm_name, "arp")


def try_get_vm_ip_dnsmasq_leases(vm_name: str) -> Optional[str]:
    mac_address = get_vm_mac_address(vm_name)
    if mac_address:
        return get_ip_from_dnsmasq_leases(mac_address)
    return None


def attempt_ip_discovery(vm_name: str) -> Optional[str]:
    """Single attempt to discover VM IP using multiple methods."""
    # Try lease source first
    ip = try_get_vm_ip_lease_source(vm_name)
    if ip:
        return ip

    # Try ARP source
    ip = try_get_vm_ip_arp_source(vm_name)
    if ip:
        return ip

    # Try dnsmasq leases
    ip = try_get_vm_ip_dnsmasq_leases(vm_name)
    if ip:
        return ip

    return None


def get_vm_ip(vm_name: str, max_tries: int = 60) -> Optional[str]:
    """Get VM IP address - main aggregator function."""
    for attempt in range(max_tries):
        ip = attempt_ip_discovery(vm_name)
        if ip:
            return ip

        # Wait before next attempt if not the last attempt
        if attempt < max_tries - 1:
            time.sleep(5)

    return None


def retry(func, max_retries: int = 30, sleep_time: int = 10, **kwargs):
    """Retry a function"""
    for i in range(max_retries):
        try:
            return func(**kwargs)
        except Exception as e:
            if i < max_retries - 1:
                logger.info(f"Retry {i + 1}/{max_retries}: {e}")
                time.sleep(sleep_time)
            else:
                raise


def apply_config(node_ip: str, config_file: Path):
    """Apply Talos config to node"""
    retry(
        lambda: commands.run(
            [
                "talosctl",
                "apply-config",
                "--insecure",
                "--nodes",
                node_ip,
                "--file",
                str(config_file),
            ]
        ),
        max_retries=30,
        sleep_time=10,
    )


def create_disk_if_not_exists(disk_size_gb: int, disk_path: Path):
    """Create a qcow2 disk if it doesn't exist."""
    if not disk_path.exists():
        create_qemu_disk(disk_size_gb, str(disk_path))


def set_disk_permissions(disk_path: Path):
    """Set appropriate permissions on disk file."""
    shutil.chown(disk_path, sudo_user, sudo_user)
    disk_path.chmod(0o644)


def create_vm_with_virt_install(
    vm_name: str,
    ram_mb: int,
    cpus: int,
    disk_options: List[str],
    extra_options: List[str] = None,
):
    """Create a VM using virt-install with common options."""
    base_command = [
        "virt-install",
        "--virt-type",
        "kvm",
        "--name",
        vm_name,
        "--ram",
        str(ram_mb),
        "--vcpus",
        str(cpus),
        "--cdrom",
        str(base_dir / ISO_NAME),
        "--os-variant",
        "linux2022",
        "--network",
        f"network={CONFIG.virtual_network.name}",
        "--graphics",
        "none",
        "--noautoconsole",
        "--boot",
        "hd,cdrom",
        "--autostart",
    ]

    # Add disk options
    for disk_option in disk_options:
        base_command.extend(["--disk", disk_option])

    # Add any extra options
    if extra_options:
        base_command.extend(extra_options)

    commands.run(base_command)


def get_cluster_directory(cluster_num: int) -> Path:
    """Get the directory path for a specific cluster."""
    return base_dir / f"cluster-{cluster_num}"


def prepare_controlplane_disk(cluster_num: int) -> Path:
    """Prepare and return control plane disk path."""
    disk_path = get_cluster_directory(cluster_num) / "cp-disk.qcow2"
    disk_path.parent.mkdir(parents=True, exist_ok=True)

    create_disk_if_not_exists(CONFIG.control_plane_node.system_disk, disk_path)
    set_disk_permissions(disk_path)

    return disk_path


def get_controlplane_disk_options(disk_path: Path) -> List[str]:
    """Get disk options for control plane VM."""
    cp = CONFIG.control_plane_node
    return [f"path={disk_path},bus=virtio,size={cp.system_disk},format=qcow2"]


def log_controlplane_creation(name: str):
    """Log control plane VM creation."""
    cp = CONFIG.control_plane_node
    logger.step(
        f"Creating Control Plane VM: {name} (cpu={cp.cpus} ram={cp.ram}MB system disk={cp.system_disk}G)"
    )


def create_controlplane_vm(name: str, cluster_num: int):
    """Create control plane VM - main aggregator function."""
    log_controlplane_creation(name)

    # Prepare disk
    disk_path = prepare_controlplane_disk(cluster_num)

    # Get disk options
    disk_options = get_controlplane_disk_options(disk_path)

    # Create VM
    create_vm_with_virt_install(
        vm_name=name,
        ram_mb=CONFIG.control_plane_node.ram,
        cpus=CONFIG.control_plane_node.cpus,
        disk_options=disk_options,
    )

    logger.ok(f"Control Plane VM created: {name}")


def prepare_worker_disks(cluster_num: int, worker_num: int) -> Tuple[Path, Path]:
    """Prepare and return worker system and storage disk paths."""
    cluster_dir = get_cluster_directory(cluster_num)
    system_disk = cluster_dir / f"worker-{worker_num}-disk.qcow2"
    storage_disk = cluster_dir / f"worker-{worker_num}-storage.qcow2"

    cluster_dir.mkdir(parents=True, exist_ok=True)

    # Create disks
    create_disk_if_not_exists(CONFIG.worker_node.system_disk, system_disk)
    create_disk_if_not_exists(CONFIG.worker_node.storage_disk, storage_disk)

    # Set permissions
    set_disk_permissions(system_disk)
    set_disk_permissions(storage_disk)

    return system_disk, storage_disk


def get_worker_disk_options(system_disk: Path, storage_disk: Path) -> List[str]:
    """Get disk options for worker VM."""
    worker = CONFIG.worker_node
    return [
        f"path={system_disk},bus=virtio,size={worker.system_disk},format=qcow2",
        f"path={storage_disk},bus=virtio,size={worker.storage_disk},format=qcow2",
    ]


def log_worker_creation(name: str):
    """Log worker VM creation."""
    worker = CONFIG.worker_node
    logger.step(
        f"Creating Worker VM: {name} (cpu={worker.cpus} ram={worker.ram}MB system disk={worker.system_disk}G + storage disk: {worker.storage_disk}G)"
    )


def create_worker_vm(name: str, cluster_num: int, worker_num: int):
    """Create worker VM with storage disk - main aggregator function."""
    log_worker_creation(name)

    # Prepare disks
    system_disk, storage_disk = prepare_worker_disks(cluster_num, worker_num)

    # Get disk options
    disk_options = get_worker_disk_options(system_disk, storage_disk)

    # Create VM
    create_vm_with_virt_install(
        vm_name=name,
        ram_mb=CONFIG.worker_node.ram,
        cpus=CONFIG.worker_node.cpus,
        disk_options=disk_options,
    )

    logger.ok(f"Worker VM created: {name}")


def check_cluster_health(cluster_num: int, cp_ip: str):
    """Check cluster health"""
    logger.step(f"Checking health of cluster-{cluster_num} (control plane: {cp_ip})")

    config_file = base_dir / f"cluster-{cluster_num}" / "configs" / "talosconfig"

    # Run health check
    env = os.environ.copy()
    env["TALOSCONFIG"] = str(config_file)

    commands.run(
        ["talosctl", "health", "-c", f"cluster-{cluster_num}", "-n", cp_ip], env=env
    )


def wait_for_port(ip: str, port: int, timeout: int = 120):
    """Wait for port to open"""
    logger.info(f"Waiting for {ip}:{port} to open...")

    for i in range(timeout // 5):
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(1)
            result = sock.connect_ex((ip, port))
            sock.close()

            if result == 0:
                logger.info(f"Port {port} is open on {ip}")
                return True

            logger.info(f"Waiting for {ip}:{port} ({i * 5}/{timeout})")
        except:
            pass

        time.sleep(5)

    return False


def ensure_time_sync():
    """Ensure host clock is synchronized before generating certificates."""
    logger.step("Synchronizing system clock")

    commands.run(["timedatectl", "set-ntp", "true"], check=False)

    # Check sync status
    result = commands.run(
        ["timedatectl", "show", "--property=NTPSynchronized"], check=False
    )
    if result.returncode == 0 and "yes" in result.stdout.lower():
        logger.ok("Clock synchronized via NTP")
    else:
        logger.warn("NTP sync not confirmed — certificate timing issues possible")


def create():
    """Main execution function"""
    global CONFIG

    CONFIG = config.load()
    require_sudo()
    setup_environment()
    setup_signal_handlers()

    check_prerequisites()
    setup_permissions()
    check_resources()

    if not confirm_proceed():
        logger.die("Cancelled")

    ensure_time_sync()
    setup_working_directory()
    download_talos_iso()
    recreate_network()

    cp_ips, worker_ips = create_and_setup_clusters()

    check_all_clusters_health(cp_ips)
    print_creation_summary(cp_ips, worker_ips)


def setup_signal_handlers():
    """Setup signal handlers."""
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)


def check_prerequisites():
    """Check all required commands exist."""
    logger.step("Checking prerequisites")
    for cmd in [
        "virsh",
        "virt-install",
        "qemu-img",
        "curl",
        "talosctl",
        "awk",
        "df",
        "free",
    ]:
        need(cmd)
    logger.ok("Prerequisites OK")


def confirm_proceed() -> bool:
    """Ask user for confirmation."""
    confirm = input("Proceed? (type yes/no): ").strip().lower()
    return confirm == "yes"


def setup_working_directory():
    """Prepare working directory."""
    logger.step("Preparing working directory")
    base_dir.mkdir(parents=True, exist_ok=True)
    shutil.chown(base_dir, sudo_user, sudo_user)
    os.chdir(base_dir)


def download_talos_iso():
    """Download Talos ISO if needed."""
    logger.step("Ensuring Talos ISO exists")
    iso_path = base_dir / ISO_NAME

    if not iso_path.exists():
        logger.info(f"Downloading {ISO_URL}")
        commands.run(
            ["curl", "--fail", "--progress-bar", "-L", ISO_URL, "-o", str(iso_path)]
        )
        logger.ok(f"ISO downloaded: {iso_path}")
    else:
        logger.ok(f"ISO already exists: {iso_path}")

    shutil.chown(iso_path, sudo_user, sudo_user)
    iso_path.chmod(0o644)


def create_and_setup_clusters() -> Tuple[dict, dict]:
    """Create VMs and setup all clusters."""
    logger.step("Creating VMs")
    cp_ips = {}
    worker_ips = {}

    for c in range(1, CONFIG.cluster_count + 1):
        setup_cluster_directory(c)
        create_controlplane_vm(f"cp-{c}", c)

        for w in range(1, CONFIG.workers_per_cluster + 1):
            create_worker_vm(f"worker-{c}-{w}", c, w)

    logger.ok("All VMs defined and started")
    logger.info("Currently running VMs:")
    commands.run(["virsh", "list"])

    logger.step("Waiting for VMs to boot and get IPs...")

    for c in range(1, CONFIG.cluster_count + 1):
        cp_ip, worker_list = setup_single_cluster(c)
        cp_ips[c] = cp_ip
        worker_ips[c] = worker_list

    return cp_ips, worker_ips


def setup_cluster_directory(cluster_num: int):
    """Setup directory structure for a cluster."""
    logger.step(f"Cluster {cluster_num}: directories")
    cluster_dir = base_dir / f"cluster-{cluster_num}"
    config_dir = cluster_dir / "configs"

    config_dir.mkdir(parents=True, exist_ok=True)
    shutil.chown(cluster_dir, sudo_user, sudo_user)
    shutil.chown(config_dir, sudo_user, sudo_user)
    cluster_dir.chmod(0o755)
    config_dir.chmod(0o755)


def setup_single_cluster(cluster_num: int) -> Tuple[str, list]:
    """Setup a single cluster completely."""
    logger.step(f"Cluster {cluster_num}: discovering node IPs")

    cp_ip = get_controlplane_ip(cluster_num)
    worker_list = get_worker_ips(cluster_num)

    generate_talos_configuration(cluster_num, cp_ip)
    apply_node_configurations(cluster_num, cp_ip, worker_list)
    bootstrap_cluster(cluster_num, cp_ip)

    return cp_ip, worker_list


def get_controlplane_ip(cluster_num: int) -> str:
    """Get control plane IP address."""
    cp_ip = get_vm_ip(f"cp-{cluster_num}", 60)
    if not cp_ip:
        logger.die(f"Failed to get IP for cp-{cluster_num}")
    logger.ok(f"cp-{cluster_num} IP: {cp_ip}")
    return cp_ip


def get_worker_ips(cluster_num: int) -> list:
    """Get all worker IP addresses."""
    worker_list = []
    for w in range(1, CONFIG.workers_per_cluster + 1):
        ip = get_vm_ip(f"worker-{cluster_num}-{w}", 60)
        if ip:
            logger.ok(f"worker-{cluster_num}-{w} IP: {ip}")
            worker_list.append(ip)
        else:
            logger.warn(f"Failed to get IP for worker-{cluster_num}-{w}")
    return worker_list


def generate_talos_configuration(cluster_num: int, cp_ip: str):
    """Generate Talos configuration files."""
    logger.step(f"Cluster {cluster_num}: generating Talos config")
    cfgdir = base_dir / f"cluster-{cluster_num}" / "configs"

    commands.run(
        [
            "talosctl",
            "gen",
            "config",
            f"cluster-{cluster_num}",
            f"https://{cp_ip}:6443",
            "--install-disk",
            "/dev/vda",
            "-o",
            str(cfgdir),
        ]
    )

    logger.ok(f"Config generated: {cfgdir}")


def apply_node_configurations(cluster_num: int, cp_ip: str, worker_list: list):
    """Apply configurations to all nodes."""
    cfgdir = base_dir / f"cluster-{cluster_num}" / "configs"

    logger.step(f"Cluster {cluster_num}: applying config (controlplane)")
    apply_config(cp_ip, cfgdir / "controlplane.yaml")
    logger.ok("Controlplane configured")

    logger.step(f"Cluster {cluster_num}: applying config (workers)")
    for ip in worker_list:
        apply_worker_config_with_storage(cluster_num, ip, cfgdir)


def apply_worker_config_with_storage(cluster_num: int, worker_ip: str, cfgdir: Path):
    """Apply storage configuration to worker node."""
    logger.step(
        f"Cluster {cluster_num}: adding storage to worker config of {worker_ip}"
    )

    patch_yaml = """machine:
  disks:
    - device: /dev/vdb
      partitions:
        - mountpoint: /var/mnt/local-path-provisioner
  files:
    - path: /etc/cri/conf.d/20-customization.part
      op: create
      content: |
        [plugins."io.containerd.cri.v1.images"]
          discard_unpacked_layers = false
"""

    with tempfile.NamedTemporaryFile(mode="w", suffix=".yaml", delete=False) as f:
        f.write(patch_yaml)
        patch_file = f.name

    try:
        worker_with_storage = cfgdir / "worker-with-storage.yaml"
        commands.run(
            [
                "talosctl",
                "machineconfig",
                "patch",
                str(cfgdir / "worker.yaml"),
                "--patch",
                f"@{patch_file}",
                "-o",
                str(worker_with_storage),
            ]
        )
        apply_config(worker_ip, worker_with_storage)
    finally:
        Path(patch_file).unlink(missing_ok=True)


def bootstrap_cluster(cluster_num: int, cp_ip: str):
    """Bootstrap Talos cluster and get kubeconfig."""
    logger.step(f"Cluster {cluster_num}: bootstrap + kubeconfig")
    cfgdir = base_dir / f"cluster-{cluster_num}" / "configs"

    talosconfig = cfgdir / "talosconfig"
    env = os.environ.copy()
    env["TALOSCONFIG"] = str(talosconfig)

    commands.run(["talosctl", "config", "endpoint", cp_ip], env=env)
    commands.run(["talosctl", "config", "node", cp_ip], env=env)

    if not wait_for_port(cp_ip, 50000, 300):
        logger.die(f"Talos API never opened on {cp_ip}")

    retry(
        lambda: commands.run(["talosctl", "-n", cp_ip, "bootstrap"], env=env),
        max_retries=30,
        sleep_time=10,
    )

    logger.ok(f"Cluster {cluster_num} bootstrapped")

    kubeconfig = base_dir / f"cluster-{cluster_num}" / "kubeconfig"
    retry(
        lambda: commands.run(
            ["talosctl", "-n", cp_ip, "kubeconfig", str(kubeconfig)], env=env
        ),
        max_retries=30,
        sleep_time=10,
    )
    shutil.chown(kubeconfig, sudo_user, sudo_user)

    logger.ok(f"Kubeconfig: {kubeconfig}")


def check_all_clusters_health(cp_ips: dict):
    """Check health of all clusters."""
    for c in range(1, CONFIG.cluster_count + 1):
        if c in cp_ips:
            check_cluster_health(c, cp_ips[c])


def print_creation_summary(cp_ips: dict, worker_ips: dict):
    """Print final creation summary."""
    print()
    logger.ok("CREATION COMPLETE")
    logger.info(f"Network: {CONFIG.virtual_network.name}")
    logger.info(f"Base dir: {base_dir}")
    print("=== Cluster IPs ===")

    for c in range(1, CONFIG.cluster_count + 1):
        print(f"Cluster {c}:")
        print(f"  Control plane: {cp_ips.get(c, 'N/A')}")
        print(f"  Workers:       {' '.join(worker_ips.get(c, []))}")
        print(f"  Kubeconfig:    {base_dir}/cluster-{c}/kubeconfig")


if __name__ == "__main__":
    create()
