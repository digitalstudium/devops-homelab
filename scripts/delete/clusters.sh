#!/bin/bash

# Function to print colored output
print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if running with sudo/root privileges
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root or with sudo"
    echo "Please run: sudo $0"
    exit 1
fi

# Confirm deletion
echo "=================================================="
echo "TALOS CLUSTERS DESTRUCTION SCRIPT"
echo "=================================================="
echo "This script will delete ALL Talos clusters and resources"
echo "Base directory: $BASE_DIR"
echo ""
echo "The following will be deleted:"
echo "1. All KVM virtual machines (control planes and workers)"
echo "2. All virtual networks"
echo "3. All disk images and configuration files"
echo "ISO files will be preserved"
echo ""
read -p "Are you sure you want to continue? (yes/no): " CONFIRM

if [[ "$CONFIRM" != "yes" ]]; then
    echo "Operation cancelled."
    exit 0
fi

echo ""
echo "Starting destruction..."

# Change to base directory
cd /opt 2>/dev/null || {
    print_error "Cannot access /opt directory"
    exit 1
}

# Check if talos-kvm directory exists
if [ ! -d "$BASE_DIR" ]; then
    print_warning "Directory $BASE_DIR does not exist. Nothing to delete."
    exit 0
fi

# Find all cluster directories
CLUSTER_DIRS=$(find "$BASE_DIR" -maxdepth 1 -type d -name "cluster-*" | sort)

if [ -z "$CLUSTER_DIRS" ]; then
    print_warning "No cluster directories found in $BASE_DIR"
else
    echo "Found cluster directories:"
    for dir in $CLUSTER_DIRS; do
        echo "  - $dir"
    done
    echo ""
fi

# Step 1: Destroy and undefine all VMs
echo "Step 1: Destroying virtual machines..."

# Find all VMs created by create-clusters.sh
# Control plane VMs: cp-1, cp-2, etc.
# Worker VMs: worker-1-1, worker-1-2, worker-2-1, etc.

VIRSH_LIST=$(virsh list --all)

# Destroy and undefine control plane VMs
for vm in $(virsh list --all --name | grep -E '^cp-[0-9]+$'); do
    echo "Processing VM: $vm"

    # Destroy if running
    if virsh domstate "$vm" | grep -q "running"; then
        echo "  - Destroying (stopping) VM..."
        virsh destroy "$vm" >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo "    VM destroyed"
        else
            print_error "Failed to destroy VM: $vm"
        fi
        sleep 2
    fi

    # Undefine VM
    echo "  - Undefining VM..."
    virsh undefine "$vm" --remove-all-storage >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        print_success "VM undefined: $vm"
    else
        print_warning "VM may already be undefined: $vm"
    fi
done

# Destroy and undefine worker VMs
for vm in $(virsh list --all --name | grep -E '^worker-[0-9]+-[0-9]+$'); do
    echo "Processing VM: $vm"

    # Destroy if running
    if virsh domstate "$vm" | grep -q "running"; then
        echo "  - Destroying (stopping) VM..."
        virsh destroy "$vm" >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo "    VM destroyed"
        else
            print_error "Failed to destroy VM: $vm"
        fi
        sleep 2
    fi

    # Undefine VM
    echo "  - Undefining VM..."
    virsh undefine "$vm" --remove-all-storage >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        print_success "VM undefined: $vm"
    else
        print_warning "VM may already be undefined: $vm"
    fi
done

echo ""

# Step 2: Destroy and undefine all networks
echo "Step 2: Destroying virtual networks..."

# Find all networks created by create-clusters.sh
# Network names: talos-net-1, talos-net-2, etc.

for net in $(virsh net-list --all --name | grep -E '^talos-net-[0-9]+$'); do
    echo "Processing network: $net"

    # Destroy if active
    if virsh net-info "$net" 2>/dev/null | grep -q "Active:.*yes"; then
        echo "  - Destroying network..."
        virsh net-destroy "$net" >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo "    Network destroyed"
        else
            print_error "Failed to destroy network: $net"
        fi
    fi

    # Undefine network
    echo "  - Undefining network..."
    virsh net-undefine "$net" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        print_success "Network undefined: $net"
    else
        print_warning "Network may already be undefined: $net"
    fi
done

echo ""

# Step 3: Remove bridge interfaces (just in case)
echo "Step 3: Cleaning up bridge interfaces..."

# Find bridge interfaces created by our networks
for br in $(ip link show | grep -oE 'talos-br-[0-9]+' | sort -u); do
    echo "Found bridge interface: $br"
    echo "  - Bringing down interface..."
    ip link set "$br" down 2>/dev/null
    echo "  - Deleting interface..."
    ip link delete "$br" 2>/dev/null
    if [ $? -eq 0 ]; then
        print_success "Bridge interface deleted: $br"
    else
        print_warning "Bridge interface may not exist: $br"
    fi
done

echo ""

# Step 4: Remove all disk images and directories
echo "Step 4: Removing disk images and directories..."

# Remove all .qcow2 files in base directory
echo "Removing disk images..."
find "$BASE_DIR" -name "*.qcow2" -type f -delete 2>/dev/null
echo "  - Disk images removed"

# Remove all configuration files
echo "Removing configuration files..."
find "$BASE_DIR" -name "*.yaml" -type f -delete 2>/dev/null
find "$BASE_DIR" -name "*.xml" -type f -delete 2>/dev/null
find "$BASE_DIR" -name "talosconfig" -type f -delete 2>/dev/null
find "$BASE_DIR" -name "kubeconfig" -type f -delete 2>/dev/null
echo "  - Configuration files removed"

# Remove ISO file (optional, can comment out if you want to keep it)
# echo "Removing ISO file..."
# rm -f "$BASE_DIR/metal-amd64.iso" 2>/dev/null
# echo "  - ISO file removed"

# Step 5: Remove everything in BASE_DIR except ISO(s)
echo "Step 5: Removing everything except ISO..."

if [ -d "$BASE_DIR" ]; then
    echo "Cleaning directory: $BASE_DIR"

    # Delete everything under BASE_DIR except *.iso files
    find "$BASE_DIR" -mindepth 1 \
      ! -name '*.iso' \
      -exec rm -rf {} + 2>/dev/null

    # Remove empty directories left behind (BASE_DIR itself is kept)
    find "$BASE_DIR" -type d -empty -delete 2>/dev/null

    print_success "Cleaned $BASE_DIR (ISO(s) preserved)"
else
    print_warning "Directory does not exist: $BASE_DIR"
fi

echo ""
echo "=================================================="
echo "DESTRUCTION COMPLETE"
echo "=================================================="
echo ""
echo "Verification:"
echo "1. Checking for remaining VMs..."
REMAINING_VMS=$(virsh list --all --name | grep -E '^(cp-[0-9]+|worker-[0-9]+-[0-9]+)$' | wc -l)
if [ "$REMAINING_VMS" -eq 0 ]; then
    print_success "No Talos VMs remaining"
else
    print_error "Found $REMAINING_VMS remaining VMs:"
    virsh list --all --name | grep -E '^(cp-[0-9]+|worker-[0-9]+-[0-9]+)$'
fi

echo ""
echo "2. Checking for remaining networks..."
REMAINING_NETS=$(virsh net-list --all --name | grep -E '^talos-net-[0-9]+$' | wc -l)
if [ "$REMAINING_NETS" -eq 0 ]; then
    print_success "No Talos networks remaining"
else
    print_error "Found $REMAINING_NETS remaining networks:"
    virsh net-list --all --name | grep -E '^talos-net-[0-9]+$'
fi

echo ""
echo "3. Checking base directory contents (should contain only .iso files)..."

if [ ! -d "$BASE_DIR" ]; then
    print_error "Base directory is missing: $BASE_DIR (expected it to remain to keep ISO(s))"
else
    # Any non-ISO regular files left?
    NON_ISO_FILES=$(find "$BASE_DIR" -type f ! -name '*.iso' -print -quit 2>/dev/null)

    if [ -n "$NON_ISO_FILES" ]; then
        print_error "Found remaining non-ISO files under: $BASE_DIR"
        echo "Example leftover:"
        echo "  $NON_ISO_FILES"
        echo "List all leftovers:"
        find "$BASE_DIR" -type f ! -name '*.iso' -print 2>/dev/null
    else
        ISO_COUNT=$(find "$BASE_DIR" -type f -name '*.iso' | wc -l)
        print_success "OK: only ISO file(s) remain in $BASE_DIR (count: $ISO_COUNT)"
    fi
fi

echo ""
echo "=================================================="
echo "All Talos clusters and resources have been removed"
echo "=================================================="
