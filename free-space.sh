#!/usr/bin/env bash
# Reclaim Docker space consumed by per-trial images/build cache after a job.
# (Or simply `docker system prune` once no jobs are running.)
set -euo pipefail

# 1. remove per-trial images (safe: skips images still used by containers)
docker ps -a --format '{{.Image}}' | sed 's/[^:]$/&:latest/' | sort -u > /tmp/keep.txt
docker images --format '{{.Repository}}:{{.Tag}}' \
  | grep -E '(-main|-pier-egress-proxy|__verifier__trial-main):latest$' \
  | grep -vxFf /tmp/keep.txt | xargs -r docker rmi

# 2. cap the build cache (keep the last 30 GB of layers)
docker builder prune -f --keep-storage 30GB
