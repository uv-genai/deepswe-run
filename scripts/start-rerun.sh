#!/usr/bin/env bash
# Detached launcher for the DeepSWE rerun.
#
#   ./scripts/start-rerun.sh                 # full rerun, job default concurrency
#   ./scripts/start-rerun.sh -n 2            # cap at 2 concurrent trials/requests
#   nohup ./scripts/start-rerun.sh -n 2 >/dev/null 2>&1 &   # detached from the start
#
# Extra arguments are forwarded to rerun-failed-trials.sh (see its header:
# optional job-dir positional and -n concurrency).
#
# All real output goes to files under log/, never to the terminal you launched
# from:
#   log/rerun-start.log   preflight + launch result (one-shot, written by rerun-failed-trials.sh)
#   log/resume.log        the benchmark's ongoing output  ->  tail -f log/resume.log
#
# The benchmark itself (pier) is detached by rerun-failed-trials.sh via its own
# nohup, so SSH can be closed as soon as this script reports the launch result.
set -euo pipefail
cd "$(dirname "$0")"

REPO="$(cd .. && pwd)"
mkdir -p "$REPO/log"
LOG="$REPO/log/rerun-start.log"
[[ -f "$LOG" ]] && mv -f "$LOG" "$LOG.prev"

./rerun-failed-trials.sh "$@" > "$LOG" 2>&1 &
LAUNCHER=$!
echo "launcher PID $LAUNCHER - preflight/launch output: $LOG"

# rerun-failed-trials.sh exits within ~1-2 min (model warm-up + 15s startup check)
if wait "$LAUNCHER"; then
  echo "=== launch OK"
  grep -E "quarantined|corrupt results|pier resume started|running\." "$LOG" || tail -5 "$LOG"
else
  echo "=== launch FAILED - last lines of $LOG:"
  tail -20 "$LOG"
  exit 1
fi

echo
echo "benchmark is running detached. Watch with:"
echo "  tail -f log/resume.log        # pier output"
echo "  ./scripts/scoreboard.sh       # live scores"
echo "  grep Traceback log/resume.log # should print nothing"
