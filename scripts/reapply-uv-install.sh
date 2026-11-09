#!/usr/bin/env bash
# Re-apply the uv-install hardening to pier's mini-swe-agent image template.
#
# pier's Dockerfile step installed uv only via the astral.sh installer, which
# chains to GitHub's release-asset CDN. That asset flapped with HTTP 504
# (2026-11-09) and killed trial builds for hours - a Python package install
# must not hinge on one URL. The patch makes the step:
#   1. retry the vendor installer (5x, bounded curl timeout)
#   2. fall back to `pip install uv==0.7.13` (PyPI) if it keeps failing
#   3. tolerate a missing ~/.local/bin/env (only the installer creates it)
#
# `uv tool upgrade datacurve-pier` wipes this edit (and the litellm pin and
# the squid read_timeout patch) - run ALL THREE reapply scripts after upgrades:
#   ./scripts/reapply-litellm-pin.sh
#   ./scripts/reapply-uv-install.sh
#   ./scripts/reapply-squid-timeout.sh
#
# Idempotent: exits 0 with a notice if the patch is already present.
set -euo pipefail

mapfile -t MSA < <(ls -1 /home/ugo/.local/share/uv/tools/datacurve-pier/lib/python*/site-packages/pier/agents/installed/mini_swe_agent.py 2>/dev/null)

die() { echo "ERROR: $*" >&2; exit 1; }

[[ ${#MSA[@]} -ge 1 ]] || die "pier mini_swe_agent.py not found - is datacurve-pier installed?"
[[ ${#MSA[@]} -eq 1 ]] || die "multiple pier installs found: ${MSA[*]}"
FILE="${MSA[0]}"
echo "target: $FILE"

if grep -q "falling back to PyPI" "$FILE"; then
  echo "already patched (uv retry + PyPI fallback) - nothing to do"
  exit 0
fi

python3 - "$FILE" <<'PY'
import sys
path = sys.argv[1]
src = open(path).read()

anchor = 'curl -LsSf https://astral.sh/uv/0.7.13/install.sh | sh\n'
if src.count(anchor) != 1:
    sys.exit(f"expected exactly 1 uv-installer line, found {src.count(anchor)} - "
             "pier's template changed, apply manually (see this script's header)")

new_block = '''# uv must come from somewhere: vendor installer first (with retries), PyPI as
# fallback. The GitHub release-asset CDN has flapped (HTTP 504, 2026-11-09) and
# killed trial builds - a Python package install must not hinge on one URL.
if ! command -v uv >/dev/null 2>&1; then
  _uv_ok=""
  for _i in 1 2 3 4 5; do
    curl -m 300 -LsSf https://astral.sh/uv/0.7.13/install.sh | sh && _uv_ok=1 && break
    sleep 15
  done
  if [ -z "$_uv_ok" ]; then
    echo "uv vendor installer kept failing - falling back to PyPI" >&2
    if ! command -v python3 >/dev/null 2>&1 || ! python3 -m pip --version >/dev/null 2>&1; then
      if command -v apt-get >/dev/null 2>&1; then apt-get update && apt-get install -y --no-install-recommends python3 python3-pip
      elif command -v apk >/dev/null 2>&1; then apk add --no-cache python3 py3-pip
      elif command -v dnf >/dev/null 2>&1; then dnf install -y python3 python3-pip
      elif command -v yum >/dev/null 2>&1; then yum install -y python3 pip
      else echo "no package manager available to install pip - aborting" >&2; exit 1
      fi
    fi
    python3 -m pip install --no-cache-dir uv==0.7.13 || python3 -m pip install --no-cache-dir --break-system-packages uv==0.7.13
  fi
fi
'''
src = src.replace(anchor, new_block + anchor, 1)

# keep the installer's env hook, but it only exists after a vendor install
env_anchor = 'source "$HOME/.local/bin/env"\n'
if src.count(env_anchor) == 1:
    src = src.replace(env_anchor,
                      'if [ -f "$HOME/.local/bin/env" ]; then . "$HOME/.local/bin/env"; fi\n', 1)

# remove the now-duplicated unconditional installer line that follows the block
leftover = 'fi\ncurl -LsSf https://astral.sh/uv/0.7.13/install.sh | sh\n'
if src.count(leftover) == 1:
    src = src.replace(leftover, 'fi\n', 1)
else:
    sys.exit(f"unexpected layout around the inserted block (leftover count "
             f"{src.count(leftover)}) - pier's template changed, apply manually")

open(path, 'w').write(src)
print("edit applied")
PY

python3 -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "$FILE" || die "edited file does not parse - restore with: uv tool upgrade --force datacurve-pier"
grep -q "falling back to PyPI" "$FILE" || die "patch marker missing after edit - check $FILE manually"
[[ "$(grep -c 'astral.sh/uv/0.7.13/install.sh' "$FILE")" == "1" ]] \
  || die "expected exactly 1 uv-installer reference after the patch - check $FILE manually"
grep -q 'curl -m 300 -LsSf https://astral.sh/uv/0.7.13/install.sh | sh && _uv_ok=1 && break' "$FILE" \
  || die "hardened retry line missing after edit - check $FILE manually"

echo "OK: uv install now retries and falls back to PyPI"
echo "note: applies to trial images built from now on (no restart needed)."
