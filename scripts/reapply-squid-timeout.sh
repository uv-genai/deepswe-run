#!/usr/bin/env bash
# Re-apply the squid read_timeout patch to pier's egress-proxy template.
#
# pier generates each trial's squid config from a heredoc in
# pier/environments/agent_setup.py; with no read_timeout directive squid uses
# its 15-minute default, and every request on the agent path is NON-streaming
# (agent -> squid -> litellm -> backend), so time-to-first-byte = full
# prefill + thinking + generation. Long-thinking models exceed 15 min and die
# with squid ERR_READ_TIMEOUT (observed: maya-glm5-l awilix, 24 kills/run).
#
# `uv tool upgrade datacurve-pier` wipes this edit - run this after every pier
# upgrade, alongside ./scripts/reapply-litellm-pin.sh.
#
# Usage: ./scripts/reapply-squid-timeout.sh [seconds]   (default 3600)
#   The value must stay ABOVE litellm's router `timeout` (litellm answers with
#   an error body at its deadline, which satisfies squid's read timer).
#
# Idempotent: exits 0 with a notice if the directive is already present.
# Applies to trial containers started from now on - no service to restart.
set -euo pipefail

READ_TIMEOUT="${1:-3600}"
[[ "$READ_TIMEOUT" =~ ^[0-9]+$ ]] || { echo "ERROR: seconds must be a number" >&2; exit 1; }

mapfile -t SETUP < <(ls -1 /home/ugo/.local/share/uv/tools/datacurve-pier/lib/python*/site-packages/pier/environments/agent_setup.py 2>/dev/null)

die() { echo "ERROR: $*" >&2; exit 1; }

[[ ${#SETUP[@]} -ge 1 ]] || die "pier agent_setup.py not found - is datacurve-pier installed?"
[[ ${#SETUP[@]} -eq 1 ]] || die "multiple pier installs found: ${SETUP[*]}"
FILE="${SETUP[0]}"
echo "target: $FILE"

if grep -q '^read_timeout [0-9]* seconds$' "$FILE"; then
  echo "already patched: $(grep -m1 '^read_timeout [0-9]* seconds$' "$FILE") - nothing to do"
  exit 0
fi

ANCHOR='cache deny all'
COUNT=$(grep -cF "$ANCHOR" "$FILE")
[[ "$COUNT" == "1" ]] || die "expected exactly 1 '$ANCHOR', found $COUNT - pier's template changed, patch manually"

python3 - "$FILE" "$ANCHOR" "$READ_TIMEOUT" <<'PY'
import sys
path, anchor, timeout = sys.argv[1:4]
src = open(path).read()
block = (
    f"{anchor}\n"
    "# DeepSWE: bound reads explicitly - squid's default read_timeout is 15 min, and\n"
    "# every request on this path is non-streaming (agent -> squid -> litellm), so\n"
    "# time-to-first-byte = full prefill + thinking + generation. Must stay ABOVE\n"
    "# litellm's router `timeout` (which answers with an error body at its deadline).\n"
    f"read_timeout {timeout} seconds\n"
)
count = src.count(anchor)
if count != 1:
    sys.exit(f"expected exactly 1 occurrence of {anchor!r}, found {count} - aborting")
open(path, "w").write(src.replace(anchor, block))
print("edit applied")
PY

python3 -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "$FILE" || die "edited file does not parse - restore with: uv tool upgrade --force datacurve-pier"
grep -q "^read_timeout ${READ_TIMEOUT} seconds$" "$FILE" || die "read_timeout not found after edit - check $FILE manually"

echo "OK: pier's squid template now sets read_timeout ${READ_TIMEOUT} seconds"
echo "note: applies to trial containers started from now on (no restart needed);"
echo "      running jobs keep the config their proxy was started with."
