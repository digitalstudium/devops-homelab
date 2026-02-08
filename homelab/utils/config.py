from dataclasses import dataclass

import tomllib

from . import logger

CONFIG_PATH = "config.toml"


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


def load():
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
