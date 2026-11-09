#!/usr/bin/env bash
# Launch the failed23 batch for one model (commit-mandate config, serial).
#
#   ./scripts/launch-failed-model.sh <model-id>
#
# Model id comes from the argument (never hardcoded); output goes to
# log/<model-id>. The engine (rerun-subset.sh) preflights and launches pier.
set -euo pipefail
cd "$(dirname "$0")/.."            # repo root

[[ $# -eq 1 ]] || { echo "ERROR: usage: $0 <model-id>" >&2; exit 1; }
MODEL="$1"
mkdir -p log

MODEL="$MODEL" nohup ./scripts/rerun-subset.sh failed23 --incremental -n 1 > "log/$MODEL" 2>&1
