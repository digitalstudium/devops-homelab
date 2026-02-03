#!/bin/bash
# manage-clusters.sh

# Configuration - set the number of clusters you want
DESIRED_CLUSTERS=2
CLUSTER_NAME_PREFIX="cluster"
BASE_CIDR="10.10.0.0/16"  # Base network that will be subdivided
MEMORY_MASTER_NODES=2.0GiB
MEMORY_WORKER_NODES=4.0GiB

# Function to generate cluster names
generate_cluster_names() {
    local names=()
    for ((i=1; i<=DESIRED_CLUSTERS; i++)); do
        names+=("${CLUSTER_NAME_PREFIX}${i}")
    done
    echo "${names[@]}"
}

# Function to generate CIDRs
generate_cidrs() {
    local cidrs=()
    local subnet_size=16
    
    for ((i=0; i<DESIRED_CLUSTERS; i++)); do
        local second_octet=$(( (i + 1) * 10 ))
        cidrs+=("10.${second_octet}.0.0/${subnet_size}")
    done
    echo "${cidrs[@]}"
}


# Initialize arrays
CLUSTERS=($(generate_cluster_names))
CIDRS=($(generate_cidrs))

create_clusters() {
    echo "Creating ${DESIRED_CLUSTERS} clusters..."
    for i in "${!CLUSTERS[@]}"; do
        echo "Creating cluster: ${CLUSTERS[$i]} with CIDR: ${CIDRS[$i]}"
        sudo --preserve-env=HOME talosctl cluster create qemu \
            --name "${CLUSTERS[$i]}" \
            --cidr "${CIDRS[$i]}" \
	    --memory "${MEMORY_MASTER_NODES}" \
	    --memory-workers "${MEMORY_WORKER_NODES}"
    done
    sudo chown -R $USER ~/.talos/
    sudo chown -R $USER ~/.kube/
}

destroy_clusters() {
    echo "Destroying ${DESIRED_CLUSTERS} clusters..."
    for cluster in "${CLUSTERS[@]}"; do
        echo "Destroying cluster: $cluster"
        sudo --preserve-env=HOME talosctl cluster destroy --name "$cluster" 
    done
    rm -rf ~/.kube/*
    rm -rf ~/.talos/{clusters,config}
}

list_clusters() {
    echo "Listing ${DESIRED_CLUSTERS} clusters..."
    for cluster in "${CLUSTERS[@]}"; do
        echo "=== Cluster: $cluster ==="
        export TALOSCONFIG=~/.talos/clusters/$cluster/talosconfig
        talosctl cluster show --provisioner qemu --name $cluster  2>/dev/null || echo "Not running"
	echo
    	echo "======================"
	echo
    done
}

case "$1" in
    create)
        create_clusters
        ;;
    destroy)
        destroy_clusters
        ;;
    list)
        list_clusters
        ;;
    *)
        echo "Usage: $0 {create|destroy|list|config}"
        echo ""
        echo "To change the number of clusters, edit the DESIRED_CLUSTERS variable"
        echo "at the top of this script (currently set to: ${DESIRED_CLUSTERS})"
        exit 1
        ;;
esac
