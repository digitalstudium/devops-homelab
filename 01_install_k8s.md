1. Install `vmkube` as it is described here: [https://github.com/digitalstudium/vmkube](https://github.com/digitalstudium/vmkube)
2. Install 2 clusters with recommended configuration:

```toml
base_dir = "/var/lib/vmkube"
cluster_count = 2
worker_nodes_per_cluster = 3
control_plane_nodes_per_cluster = 1

registries = [
    { remote = "docker.io", port = 5000 },
    { remote = "registry.k8s.io", port = 5001 },
    { remote = "gcr.io", port = 5002 },
    { remote = "ghcr.io", port = 5003 },
    { remote = "registry-1.docker.io", port = 5004 },
    { remote = "mirror.gcr.io", port = 5005 },
    { remote = "quay.io", port = 5006 },
]

[control_plane_node]
cpus = 4
ram = 4096
system_disk = 7

[worker_node]
cpus = 8
ram = 8192
system_disk = 15
storage_disk = 10

[virtual_network]
name = "vmkube-net"
bridge = "vmkube-br0"
subnet = "192.168.192.0"
```
