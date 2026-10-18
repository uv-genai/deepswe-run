#!/usr/bin/env bash
# Re-apply the litellm==1.105.1 pin to pier's mini-swe-agent install spec.
#
# `uv tool upgrade datacurve-pier` reinstalls the package and wipes the edit,
# after which every newly built trial image picks up the latest litellm again
# (1.106.0+ breaks trials with "No module named 'mcp'"). Run this after every
# pier upgrade, and before starting any benchmark run.
#
# Idempotent: exits 0 with a notice if the pin is already present.
set -euo pipefail

PIN='litellm==1.105.1'
# uv tool lib dir uses the current python version (may change across upgrades)
mapfile -t MSA < <(ls -1 /home/ugo/.local/share/uv/tools/datacurve-pier/lib/python*/site-packages/pier/agents/installed/mini_swe_agent.py 2>/dev/null)

die() { echo "ERROR: $*" >&2; exit 1; }

[[ ${#MSA[@]} -ge 1 ]] || die "pier mini_swe_agent.py not found - is datacurve-pier installed? (uv tool install datacurve-pier)"
[[ ${#MSA[@]} -eq 1 ]] || die "multiple pier installs found: ${MSA[*]}"
FILE="${MSA[0]}"
echo "target: $FILE"

# already pinned?
if grep -q -- "$PIN" "$FILE"; then
  echo "already pinned ($PIN) - nothing to do"
  exit 0
fi

# the install line inside the f-string (exact form pier has shipped)
TARGET='uv tool install mini-swe-agent{version_spec}'
if ! grep -qF "$TARGET" "$FILE"; then
  echo "expected line not found. Candidates in $FILE:" >&2
  grep -n "uv tool install mini-swe-agent" "$FILE" >&2 || true
  die "pier's install command changed in this version - reapply the pin manually: add --with \"$PIN\" to the uv tool install line"
fi

# idempotent-safe in-place edit (single occurrence)
python3 - "$FILE" "$TARGET" "$PIN" <<'PY'
import sys
path, target, pin = sys.argv[1:4]
src = open(path).read()
new = f'{target} --with "{pin}"'
count = src.count(target)
if count != 1:
    sys.exit(f"expected exactly 1 occurrence, found {count} - aborting")
open(path, "w").write(src.replace(target, new))
print("edit applied")
PY

# verify: parses, and pin present in an install line
python3 -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "$FILE" || die "edited file does not parse - restore with: uv tool upgrade --force datacurve-pier"
grep -qF "uv tool install mini-swe-agent{version_spec} --with \"$PIN\"" "$FILE" || die "pin not found after edit - check $FILE manually"

echo "OK: pier now installs mini-swe-agent with $PIN"
echo "note: fresh images rebuild automatically (install fingerprint changed);"
echo "      running jobs are unaffected - the pin applies to newly built trials only."
