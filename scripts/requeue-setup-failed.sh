#!/usr/bin/env bash
# Re-queue trials that died at ENVIRONMENT SETUP (docker compose / image-build
# failure) so `pier job resume` runs them again.
#
# A setup failure means the agent never started: no steps, no reward.json, and
# result.json records RuntimeError (observed cause: transient GitHub 504 while
# the Dockerfile installs uv,2026-11-08 - 5 of 22 trials in the glm-m failed23
# arm). Those trials must not be counted against the model; everything already
# graded stays untouched.
#
# Evidence is preserved: failed trial dirs are moved to
#   <job>/.infra-failed-backup/        (handoff §3 convention)
# before resuming, so pier sees them as missing and re-runs only those tasks.
#
# Config: no flag needed - the agent config (e.g. commit-incremental.yaml) was
# baked into the job at launch (`--ak config_yaml=...`); `pier job resume`
# re-applies it. The script verifies that and warns if it is absent.
#
# Usage:
#   ./scripts/requeue-setup-failed.sh jobs/<job-dir> [--dry]
#   --dry   list what would be re-queued, move nothing, launch nothing
set -euo pipefail
cd "$(dirname "$0")/.."

JOB=""; DRY=0
for a in "$@"; do
  case "$a" in
    --dry) DRY=1 ;;
    -*) echo "unknown flag: $a" >&2; exit 1 ;;
    *) [[ -z "$JOB" ]] || { echo "only one job dir expected" >&2; exit 1; }; JOB="$a" ;;
  esac
done

die() { echo "ERROR: $*" >&2; exit 1; }
[[ -n "$JOB" ]] || die "usage: $0 jobs/<job-dir> [--dry]"
JOB="${JOB%/}"
[[ -d "$JOB" ]] || die "not a directory: $JOB"
[[ -f "$JOB/config.json" ]] || die "not a pier job dir (no config.json): $JOB"

# ---------- find setup-failed, ungraded trials ----------
mapfile -t CAND < <(python3 - "$JOB" <<'PY'
import json, glob, os, sys
job = sys.argv[1]
for f in sorted(glob.glob(job + '/*/result.json')):
    d = os.path.dirname(f)
    if os.path.exists(os.path.join(d, 'verifier', 'reward.json')):
        continue                      # graded -> never touch
    try:
        r = json.load(open(f))
    except Exception:
        continue                      # corrupt -> rerun-failed-trials.sh's own job
    if r.get('n_agent_steps'):
        continue                      # agent ran -> not a setup failure
    e = r.get('exception_info') or {}
    if e.get('exception_type') == 'RuntimeError' and 'compose' in str(e.get('exception_message', '')):
        print(d)
PY
)

if [[ ${#CAND[@]} -eq 0 ]]; then
  echo "no setup-failed ungraded trials found in $JOB - nothing to do"
  exit 0
fi

echo "setup-failed trials to re-queue (${#CAND[@]}):"
printf '  %s\n' "${CAND[@]##*/}"

# ---------- config sanity: resume reuses the job's baked-in agent config ----------
if grep -q "config_yaml" "$JOB/config.json" && grep -q "Commit Incremental Work" "$JOB/config.json"; then
  echo "agent config: commit-incremental is baked into the job config - resume re-applies it"
else
  echo "WARNING: $JOB/config.json does not contain the commit-incremental config" >&2
  echo "         (re-runs would use stock mini-swe - check how the job was launched)" >&2
fi

[[ "$DRY" == 1 ]] && { echo "--dry: nothing moved, nothing launched"; exit 0; }

# ---------- safety: never move dirs under a running job ----------
pgrep -f "bin/python .*pier (run|job resume)" >/dev/null \
  && die "a pier job is already running - wait for it to finish first"

mkdir -p "$JOB/.infra-failed-backup"
for d in "${CAND[@]}"; do
  mv "$d" "$JOB/.infra-failed-backup/"
  echo "quarantined: ${d##*/}"
done

echo "resuming (only the missing trials re-run):"
exec ./scripts/rerun-failed-trials.sh "$JOB"
