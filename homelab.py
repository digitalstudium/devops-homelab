#!/usr/bin/env python3
import sys

import homelab.argocd as argocd
import homelab.clusters as clusters

COMMANDS = {
    "up": clusters.create,
    "down": clusters.cleanup,
    "argocd": argocd.install,
}


def main():
    if len(sys.argv) < 2 or sys.argv[1] in ("-h", "--help"):
        print("Usage: homelab.py <command>")
        print()
        print("Commands:")
        print("  up     Create clusters and VMs")
        print("  down   Destroy all clusters and VMs")
        sys.exit(0)

    command = sys.argv[1]
    if command not in COMMANDS:
        print(f"Unknown command: '{command}'")
        print(f"Available commands: {', '.join(COMMANDS)}")
        sys.exit(1)

    COMMANDS[command]()


if __name__ == "__main__":
    main()
