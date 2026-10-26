#!/usr/bin/env bash
# Re-run all HARD-ZERO tasks (reward 0, f2p < 50%, incl. the verifier-timeout
# task) from the finished main gufo job, as a fresh job. See rerun-subset.sh.
set -euo pipefail
cd "$(dirname "$0")"
exec ./rerun-subset.sh zeros "$@"
