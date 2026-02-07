#!/usr/bin/env python3
import sys

import homelab.clusters as clusters

if sys.argv[1] == "up":
    clusters.create()
elif sys.argv[1] == "down":
    clusters.cleanup()
