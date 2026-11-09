#!/usr/bin/env bash
# Re-run all NEAR-MISS tasks (reward 0, f2p >= 50%) from the finished main
# job of $MODEL, as a fresh job. See rerun-subset.sh (MODEL env var required).
set -euo pipefail
cd "$(dirname "$0")"
exec ./rerun-subset.sh nearmiss "$@"
