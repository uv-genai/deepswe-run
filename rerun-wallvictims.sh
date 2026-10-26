#!/usr/bin/env bash
# Re-run the 6 tasks that died on the 262144-token context wall
# (HANDOFF-20261024-1902.md §5), WITH the commit-incremental agent config
# (commit after each feature) - the wall is a server-side fix (--context
# raised by the operator); this part is the client-side half.
set -euo pipefail
cd "$(dirname "$0")"
exec ./rerun-subset.sh wallvictims --incremental "$@"
