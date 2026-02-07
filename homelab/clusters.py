#!/usr/bin/env python3
import os
import pwd
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional

import tomllib

from homelab.utils import logger

# constants
NETWORK_NETMASK = "255.255.248.0"
ISO_NAME = "metal-amd64.iso"
ISO_URL = f"https://github.com/siderolabs/talos/releases/latest/download/{ISO_NAME}"
CONFIG_PATH = "config.toml"


# variables
CONFIG = None


def need(cmd: str):
    """Check if command exists"""
    if shutil.which(cmd) is None:
        logger.die(f"Missing required command: {cmd}")


def mb2gb(mb: int) -> float:
    """Convert MB to GB"""
    return mb / 1024


@dataclass
class ControlPlaneNode:
    cpus: int
    ram: int
    system_disk: int


@dataclass
class WorkerNode:
    cpus: int
    ram: int
    system_disk: int
    storage_disk: int


@dataclass
class VirtualNetwork:
    name: str
    bridge: str
    subnet: str


@dataclass
class Config:
    base_dir: str
    cluster_count: int
    workers_per_cluster: int
    control_plane_node: ControlPlaneNode
    worker_node: WorkerNode
    virtual_network: VirtualNetwork


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
    run_command(
        [
            "qemu-img",
            "create",
            "-f",
            "qcow2",
            str(disk_path),
            f"{size}G",
        ]
    )


def run_command(
    cmd: List[str], check: bool = True, **kwargs
) -> subprocess.CompletedProcess:
    """Run a command and return the result"""
    try:
        # Print the command for debugging
        logger.info(f"Running command: {' '.join(cmd)}")
        result = subprocess.run(
            cmd, check=check, capture_output=True, text=True, **kwargs
        )
        # Always print output for debugging
        if result.stdout:
            logger.info(f"STDOUT: {result.stdout}")
        if result.stderr:
            logger.info(f"STDERR: {result.stderr}")
        return result
    except subprocess.CalledProcessError as e:
        logger.error(f"Command failed with exit code {e.returncode}")
        logger.error(f"Command: {' '.join(e.cmd)}")
        if e.stdout:
            logger.error(f"STDOUT: {e.stdout}")
        if e.stderr:
            logger.error(f"STDERR: {e.stderr}")
        if check:
            raise
        return e


def load_config():
    """Load configuration from TOML file"""
    try:
        with open(CONFIG_PATH, "rb") as f:
            config_data = tomllib.load(f)

        # Create config object
        config = Config(
            base_dir=config_data["base_dir"],
            cluster_count=config_data["cluster_count"],
            workers_per_cluster=config_data["workers_per_cluster"],
            control_plane_node=ControlPlaneNode(**config_data["control_plane_node"]),
            worker_node=WorkerNode(**config_data["worker_node"]),
            virtual_network=VirtualNetwork(**config_data["virtual_network"]),
        )

        logger.info(f"Configuration loaded from {CONFIG_PATH}")
        return config

    except Exception as e:
        logger.die(f"Failed to load config: {e}")


class TalosKVM:
    def __init__(self):
        self.require_sudo()
        self.setup_environment()
        self.cleanup_needed = False
        self.network_created = False

        # Signal handling for cleanup
        signal.signal(signal.SIGINT, self.signal_handler)
        signal.signal(signal.SIGTERM, self.signal_handler)

    def setup_environment(self):
        """Setup environment variables and permissions"""
        logger.step("Setting up environment")
        self.setup_sudo_user()
        self.setup_base_dir()
        self.setup_netwok_config()
        logger.info(f"Base directory: {self.base_dir}")
        logger.info(f"User: {self.sudo_user}")

    def require_sudo(self):
        if os.geteuid() != 0:
            logger.die("Run with sudo!")

    def setup_sudo_user(self):
        self.sudo_user = os.environ.get("SUDO_USER")
        if not self.sudo_user:
            logger.die("Run via sudo from a normal user (SUDO_USER empty)")

    def setup_base_dir(self):
        self.base_dir = Path(CONFIG.base_dir)

    def setup_netwok_config(self):
        self.network_gateway = get_network_gateway(CONFIG)
        self.dhcp_start = get_dhcp_start(CONFIG)
        self.dhcp_end = get_dhcp_end(CONFIG)

    def signal_handler(self, signum, frame):
        """Handle signals for cleanup"""
        print("\n")
        logger.warn("Script interrupted -> cleanup, please wait for a while...")
        self.cleanup()
        sys.exit(1)

    def cleanup(self):
        """Cleanup resources on failure"""
        if not self.cleanup_needed:
            return

        logger.info("Cleaning up resources...")

        # Destroy VMs
        for c in range(1, CONFIG.cluster_count + 1):
            run_command(["virsh", "destroy", f"cp-{c}"], check=False)
            run_command(
                ["virsh", "undefine", f"cp-{c}", "--remove-all-storage"], check=False
            )

            for w in range(1, CONFIG.workers_per_cluster + 1):
                run_command(["virsh", "destroy", f"worker-{c}-{w}"], check=False)
                run_command(
                    ["virsh", "undefine", f"worker-{c}-{w}", "--remove-all-storage"],
                    check=False,
                )

        # Remove network
        if self.network_created:
            run_command(
                ["virsh", "net-destroy", CONFIG.virtual_network.name], check=False
            )
            run_command(
                ["virsh", "net-undefine", CONFIG.virtual_network.name], check=False
            )

            # Remove leftover bridge
            if self.check_bridge_exists():
                run_command(
                    ["ip", "link", "set", CONFIG.virtual_network.bridge, "down"],
                    check=False,
                )
                run_command(
                    [
                        "ip",
                        "link",
                        "delete",
                        CONFIG.virtual_network.bridge,
                        "type",
                        "bridge",
                    ],
                    check=False,
                )

    def check_bridge_exists(self) -> bool:
        """Check if network bridge exists"""
        result = run_command(
            ["ip", "link", "show", CONFIG.virtual_network.bridge], check=False
        )
        return result.returncode == 0

    def setup_permissions(self):
        """Setup permissions for directories"""
        logger.step("Setting up permissions")

        # Create base directory
        self.base_dir.mkdir(parents=True, exist_ok=True)

        # Set ownership
        shutil.chown(self.base_dir, self.sudo_user, self.sudo_user)
        self.base_dir.chmod(0o755)

        # Determine libvirt user
        libvirt_user = "libvirt-qemu"
        try:
            import pwd

            pwd.getpwnam("libvirt-qemu")
        except KeyError:
            libvirt_user = "qemu"

        # Set ACLs if available
        if shutil.which("setfacl"):
            run_command(
                ["setfacl", "-m", f"u:{libvirt_user}:rx", str(self.base_dir)],
                check=False,
            )
            logger.info(f"ACL set for {libvirt_user}")
        else:
            logger.warn("setfacl not found; falling back to chmod")
            self.base_dir.chmod(0o755)

        logger.ok("Permissions set")

    def check_resources(self):
        """Check system resources"""
        logger.step("Checking system resources")

        # Calculate required resources
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

        # Get available resources
        avail_cpu = os.cpu_count()

        # Get RAM
        with open("/proc/meminfo", "r") as f:
            for line in f:
                if line.startswith("MemTotal:"):
                    avail_ram = int(line.split()[1]) // 1024  # Convert kB to MB
                    break

        # Get disk space
        stat = shutil.disk_usage(self.base_dir)
        avail_disk = stat.free // (1024**3)  # Convert to GB

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
        logger.info("=== AVAILABLE ===")
        logger.info(f"CPU cores: {avail_cpu}")
        logger.info(f"RAM:       {mb2gb(avail_ram):.2f}GB")
        logger.info(f"Disk free: {avail_disk} GB (checked at {self.base_dir})")
        print()

        # Check for overcommit
        if total_cpu > avail_cpu:
            logger.warn(
                f"CPU overcommit: requested {total_cpu} vCPU > {avail_cpu} cores"
            )

        if total_ram > avail_ram:
            logger.warn(
                f"RAM overcommit: requested {mb2gb(total_ram):.2f}GB > available {mb2gb(avail_ram):.2f}GB"
            )

        if total_disk > avail_disk:
            logger.die(
                f"Insufficient disk: need {total_disk}GB free, have {avail_disk}GB"
            )

        # Check KVM
        if not Path("/dev/kvm").exists():
            logger.die("KVM not available (/dev/kvm missing)")

        # Check libvirtd
        result = run_command(["systemctl", "is-active", "libvirtd"], check=False)
        if result.returncode != 0:
            logger.die("libvirtd is not running")

        logger.ok("Resource check passed")

    def recreate_network(self):
        """Recreate libvirt network"""
        logger.step(f"Recreating libvirt network: {CONFIG.virtual_network.name}")

        # Remove existing network
        result = run_command(
            ["virsh", "net-info", CONFIG.virtual_network.name], check=False
        )
        if result.returncode == 0:
            logger.info(
                f"Destroy/undefine existing network '{CONFIG.virtual_network.name}'"
            )
            run_command(
                ["virsh", "net-destroy", CONFIG.virtual_network.name], check=False
            )
            run_command(
                ["virsh", "net-undefine", CONFIG.virtual_network.name], check=False
            )

        # Remove leftover bridge
        if self.check_bridge_exists():
            logger.info(f"Removing leftover bridge '{CONFIG.virtual_network.bridge}'")
            run_command(
                ["ip", "link", "set", CONFIG.virtual_network.bridge, "down"],
                check=False,
            )
            run_command(
                [
                    "ip",
                    "link",
                    "delete",
                    CONFIG.virtual_network.bridge,
                    "type",
                    "bridge",
                ],
                check=False,
            )

        # Create network XML
        network_xml = f"""<network>
  <name>{CONFIG.virtual_network.name}</name>
  <bridge name="{CONFIG.virtual_network.bridge}" stp="off" delay="0"/>
  <forward mode="nat">
    <nat><port start="1024" end="65535"/></nat>
  </forward>
  <ip address="{self.network_gateway}" netmask="{NETWORK_NETMASK}">
    <dhcp><range start="{self.dhcp_start}" end="{self.dhcp_end}"/></dhcp>
  </ip>
</network>"""

        # Write XML to temp file
        with tempfile.NamedTemporaryFile(mode="w", suffix=".xml", delete=False) as f:
            f.write(network_xml)
            xml_file = f.name

        try:
            # Define and start network
            run_command(["virsh", "net-define", xml_file])
            run_command(["virsh", "net-start", CONFIG.virtual_network.name])
            run_command(["virsh", "net-autostart", CONFIG.virtual_network.name])
            self.network_created = True

            logger.ok(
                f"Network active: {CONFIG.virtual_network.name} (bridge={CONFIG.virtual_network.bridge}, gw={self.network_gateway}, dhcp={self.dhcp_start}-{self.dhcp_end})"
            )

            # Wait for dnsmasq lease file
            lease_file = Path(
                f"/var/lib/libvirt/dnsmasq/{CONFIG.virtual_network.name}.leases"
            )
            for _ in range(20):
                if lease_file.exists():
                    break
                time.sleep(1)

        finally:
            Path(xml_file).unlink(missing_ok=True)

    def get_vm_ip(self, vm_name: str, max_tries: int = 60) -> Optional[str]:
        """Get VM IP address"""
        for i in range(max_tries):
            # Try lease source first
            result = run_command(
                ["virsh", "domifaddr", vm_name, "--source", "lease"], check=False
            )
            if result.returncode == 0:
                for line in result.stdout.splitlines():
                    if "ipv4" in line:
                        ip = line.split()[3].split("/")[0]
                        if ip and not ip.startswith("127."):
                            return ip

            # Try ARP source
            result = run_command(
                ["virsh", "domifaddr", vm_name, "--source", "arp"], check=False
            )
            if result.returncode == 0:
                for line in result.stdout.splitlines():
                    if "ipv4" in line:
                        ip = line.split()[3].split("/")[0]
                        if ip and not ip.startswith("127."):
                            return ip

            # Try reading from dnsmasq leases
            lease_file = Path(
                f"/var/lib/libvirt/dnsmasq/{CONFIG.virtual_network.name}.leases"
            )
            if lease_file.exists():
                # Get MAC address
                result = run_command(["virsh", "domiflist", vm_name], check=False)
                if result.returncode == 0:
                    for line in result.stdout.splitlines():
                        if CONFIG.virtual_network.name in line:
                            parts = line.split()
                            if len(parts) >= 5:
                                mac = parts[4].lower()
                                break

                    if "mac" in locals():
                        with open(lease_file, "r") as f:
                            for lease_line in f:
                                parts = lease_line.split()
                                if len(parts) >= 3 and parts[1].lower() == mac:
                                    ip = parts[2]
                                    if ip and not ip.startswith("127."):
                                        return ip

            if i < max_tries - 1:
                time.sleep(5)

        return None

    def retry(self, func, max_retries: int = 30, sleep_time: int = 10, **kwargs):
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

    def apply_config(self, node_ip: str, config_file: Path):
        """Apply Talos config to node"""
        self.retry(
            lambda: run_command(
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

    def create_controlplane_vm(self, name: str, cluster_num: int):
        """Create control plane VM"""
        cp = CONFIG.control_plane_node
        logger.step(
            f"Creating Control Plane VM: {name} (cpu={cp.cpus} ram={cp.ram}MB system disk={cp.system_disk}G)"
        )

        disk_path = self.base_dir / f"cluster-{cluster_num}" / "cp-disk.qcow2"
        disk_path.parent.mkdir(parents=True, exist_ok=True)

        # Create disk if it doesn't exist
        if not disk_path.exists():
            create_qemu_disk(cp.system_disk, str(disk_path))

        # Set permissions
        shutil.chown(disk_path, self.sudo_user, self.sudo_user)
        disk_path.chmod(0o644)

        # Create VM
        run_command(
            [
                "virt-install",
                "--virt-type",
                "kvm",
                "--name",
                name,
                "--ram",
                str(cp.ram),
                "--vcpus",
                str(cp.cpus),
                "--disk",
                f"path={disk_path},bus=virtio,size={cp.system_disk},format=qcow2",
                "--cdrom",
                str(self.base_dir / ISO_NAME),
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
        )

        logger.ok(f"Control Plane VM created: {name}")

    def create_worker_vm(self, name: str, cluster_num: int, worker_num: int):
        """Create worker VM with storage disk"""
        worker = CONFIG.worker_node
        logger.step(
            f"Creating Worker VM: {name} (cpu={worker.cpus} ram={worker.ram}MB system disk={worker.system_disk}G + storage disk: {worker.storage_disk}G)"
        )

        cluster_dir = self.base_dir / f"cluster-{cluster_num}"
        system_disk = cluster_dir / f"worker-{worker_num}-disk.qcow2"
        storage_disk = cluster_dir / f"worker-{worker_num}-storage.qcow2"

        cluster_dir.mkdir(parents=True, exist_ok=True)

        # Create system disk
        if not system_disk.exists():
            run_command(
                [
                    "qemu-img",
                    "create",
                    "-f",
                    "qcow2",
                    str(system_disk),
                    f"{worker.system_disk}G",
                ]
            )

        # Create storage disk
        if not storage_disk.exists():
            run_command(
                [
                    "qemu-img",
                    "create",
                    "-f",
                    "qcow2",
                    str(storage_disk),
                    f"{worker.storage_disk}G",
                ]
            )

        # Set permissions
        shutil.chown(system_disk, self.sudo_user, self.sudo_user)
        shutil.chown(storage_disk, self.sudo_user, self.sudo_user)
        system_disk.chmod(0o644)
        storage_disk.chmod(0o644)

        # Create VM
        run_command(
            [
                "virt-install",
                "--virt-type",
                "kvm",
                "--name",
                name,
                "--ram",
                str(worker.ram),
                "--vcpus",
                str(worker.cpus),
                "--disk",
                f"path={system_disk},bus=virtio,size={worker.system_disk},format=qcow2",
                "--disk",
                f"path={storage_disk},bus=virtio,size={worker.storage_disk},format=qcow2",
                "--cdrom",
                str(self.base_dir / ISO_NAME),
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
        )

        logger.ok(f"Worker VM created: {name}")

    def check_cluster_health(self, cluster_num: int, cp_ip: str):
        """Check cluster health"""
        logger.step(
            f"Checking health of cluster-{cluster_num} (control plane: {cp_ip})"
        )

        config_file = (
            self.base_dir / f"cluster-{cluster_num}" / "configs" / "talosconfig"
        )

        # Run health check
        env = os.environ.copy()
        env["TALOSCONFIG"] = str(config_file)

        run_command(
            ["talosctl", "health", "-c", f"cluster-{cluster_num}", "-n", cp_ip], env=env
        )

    def wait_for_port(self, ip: str, port: int, timeout: int = 120):
        """Wait for port to open"""
        import socket

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

    def main(self):
        """Main execution function"""
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

        self.setup_permissions()
        self.check_resources()

        # Ask for confirmation
        confirm = input("Proceed? (type yes/no): ").strip().lower()
        if confirm != "yes":
            logger.die("Cancelled")

        # Prepare working directory
        logger.step("Preparing working directory")
        self.base_dir.mkdir(parents=True, exist_ok=True)
        shutil.chown(self.base_dir, self.sudo_user, self.sudo_user)
        os.chdir(self.base_dir)

        # Download Talos ISO
        logger.step("Ensuring Talos ISO exists")
        iso_path = self.base_dir / ISO_NAME

        if not iso_path.exists():
            logger.info(f"Downloading {ISO_URL}")
            run_command(
                [
                    "curl",
                    "--fail",
                    "--progress-bar",
                    "-L",
                    ISO_URL,
                    "-o",
                    str(iso_path),
                ]
            )
            logger.ok(f"ISO downloaded: {iso_path}")
        else:
            logger.ok(f"ISO already exists: {iso_path}")

        shutil.chown(iso_path, self.sudo_user, self.sudo_user)
        iso_path.chmod(0o644)

        self.cleanup_needed = True

        # Recreate network
        self.recreate_network()

        # Create VMs
        logger.step("Creating VMs")
        cp_ips = {}
        worker_ips = {}

        for c in range(1, CONFIG.cluster_count + 1):
            logger.step(f"Cluster {c}: directories")
            cluster_dir = self.base_dir / f"cluster-{c}"
            config_dir = cluster_dir / "configs"

            config_dir.mkdir(parents=True, exist_ok=True)
            shutil.chown(cluster_dir, self.sudo_user, self.sudo_user)
            shutil.chown(config_dir, self.sudo_user, self.sudo_user)
            cluster_dir.chmod(0o755)
            config_dir.chmod(0o755)

            # Create control plane VM
            self.create_controlplane_vm(f"cp-{c}", c)

            # Create worker VMs
            for w in range(1, CONFIG.workers_per_cluster + 1):
                self.create_worker_vm(f"worker-{c}-{w}", c, w)

        logger.ok("All VMs defined and started")

        # List running VMs
        logger.info("Currently running VMs:")
        run_command(["virsh", "list"])

        logger.step("Waiting for VMs to boot and get IPs...")

        for c in range(1, CONFIG.cluster_count + 1):
            logger.step(f"Cluster {c}: discovering node IPs")

            # Get control plane IP
            cp_ip = self.get_vm_ip(f"cp-{c}", 60)
            if not cp_ip:
                logger.die(f"Failed to get IP for cp-{c}")
            logger.ok(f"cp-{c} IP: {cp_ip}")
            cp_ips[c] = cp_ip

            # Get worker IPs
            worker_list = []
            for w in range(1, CONFIG.workers_per_cluster + 1):
                ip = self.get_vm_ip(f"worker-{c}-{w}", 60)
                if ip:
                    logger.ok(f"worker-{c}-{w} IP: {ip}")
                    worker_list.append(ip)
                else:
                    logger.warn(f"Failed to get IP for worker-{c}-{w}")

            worker_ips[c] = worker_list

            # Generate Talos config
            logger.step(f"Cluster {c}: generating Talos config")
            cfgdir = self.base_dir / f"cluster-{c}" / "configs"

            run_command(
                [
                    "talosctl",
                    "gen",
                    "config",
                    f"cluster-{c}",
                    f"https://{cp_ip}:6443",
                    "--install-disk",
                    "/dev/vda",
                    "-o",
                    str(cfgdir),
                ]
            )

            logger.ok(f"Config generated: {cfgdir}")

            # Apply control plane config
            logger.step(f"Cluster {c}: applying config (controlplane)")
            self.apply_config(cp_ip, cfgdir / "controlplane.yaml")
            logger.ok("Controlplane configured")

            # Apply worker configs with storage modifications
            logger.step(f"Cluster {c}: applying config (workers)")
            for ip in worker_list:
                logger.step(f"Cluster {c}: adding storage to worker config of {ip}")

                # Create patch for storage
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

                # Write patch to temp file
                with tempfile.NamedTemporaryFile(
                    mode="w", suffix=".yaml", delete=False
                ) as f:
                    f.write(patch_yaml)
                    patch_file = f.name

                try:
                    # Patch worker config
                    worker_with_storage = cfgdir / "worker-with-storage.yaml"
                    run_command(
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

                    # Apply the patched config
                    self.apply_config(ip, worker_with_storage)
                finally:
                    Path(patch_file).unlink(missing_ok=True)

            # Bootstrap cluster
            logger.step(f"Cluster {c}: bootstrap + kubeconfig")
            talosconfig = cfgdir / "talosconfig"
            env = os.environ.copy()
            env["TALOSCONFIG"] = str(talosconfig)

            # Set endpoints and nodes
            run_command(
                ["talosctl", "config", "endpoint", cp_ip],
                env=env,
            )

            run_command(
                ["talosctl", "config", "node", cp_ip],
                env=env,
            )

            # Wait for Talos API
            if not self.wait_for_port(cp_ip, 50000, 120):
                logger.die(f"Talos API never opened on {cp_ip}")

            # Bootstrap
            self.retry(
                lambda: run_command(
                    ["talosctl", "-n", cp_ip, "bootstrap"],
                    env=env,
                ),
                max_retries=30,
                sleep_time=10,
            )

            logger.ok(f"Cluster {c} bootstrapped")

            # Get kubeconfig
            kubeconfig = self.base_dir / f"cluster-{c}" / "kubeconfig"
            self.retry(
                lambda: run_command(
                    ["talosctl", "-n", cp_ip, "kubeconfig", str(kubeconfig)],
                    env=env,
                ),
                max_retries=30,
                sleep_time=10,
            )

            logger.ok(f"Kubeconfig: {kubeconfig}")

        # Check cluster health
        for c in range(1, CONFIG.cluster_count + 1):
            if c in cp_ips:
                self.check_cluster_health(c, cp_ips[c])

        self.cleanup_needed = False

        # Print summary
        print()
        logger.ok("CREATION COMPLETE")
        logger.info(f"Network: {CONFIG.virtual_network.name}")
        logger.info(f"Base dir: {self.base_dir}")
        print("=== Cluster IPs ===")

        for c in range(1, CONFIG.cluster_count + 1):
            print(f"Cluster {c}:")
            print(f"  Control plane: {cp_ips.get(c, 'N/A')}")
            print(f"  Workers:       {' '.join(worker_ips.get(c, []))}")
            print(f"  Kubeconfig:    {self.base_dir}/cluster-{c}/kubeconfig")


def create():
    global CONFIG
    CONFIG = load_config()
    talos_kvm = TalosKVM()
    talos_kvm.main()


if __name__ == "__main__":
    create()
