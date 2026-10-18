#!/usr/bin/env bash
# Detached launcher for the DeepSWE rerun.
#
#   ./start-rerun.sh            # foreground: shows launch outcome in ~1-2 min, then exits
#   nohup ./start-rerun.sh >/dev/null 2>&1 &   # fully detached from the start
#
# All real output goes to files, never to the terminal you launched from:
#   rerun-start.log   preflight + launch result (one-shot, written by rerun-failed-trials.sh)
#   resume.log        the benchmark's ongoing output  ->  tail -f resume.log
#
# The benchmark itself (pier) is detached by rerun-failed-trials.sh via its own
# nohup, so SSH can be closed as soon as this script reports the launch result.
set -euo pipefail
cd "$(dirname "$0")"

LOG=rerun-start.log
[[ -f "$LOG" ]] && mv -f "$LOG" "$LOG.prev"

./rerun-failed-trials.sh > "$LOG" 2>&1 &
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
echo "  tail -f resume.log        # pier output"
echo "  ./scoreboard.sh           # live scores"
echo "  grep Traceback resume.log # should print nothing"
