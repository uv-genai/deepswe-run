#!/usr/bin/env bash
# Re-run the 13 remaining zero tasks from the zeros-rerun batch, WITH the
# commit-incremental agent config (commit after each feature - 7 of the 13
# previously lost all work to the discarded-at-submit failure mode; see
# reports/zeros-rerun-analysis-2026-10-21.md).
set -euo pipefail
cd "$(dirname "$0")"
exec ./rerun-subset.sh failed13 --incremental "$@"
