#!/usr/bin/env bash
# Re-run the gufo DeepSWE job: keep every trial graded BEFORE the litellm 1.106.0
# breakage, re-queue all trials poisoned by "No module named 'mcp'" plus whatever
# was still pending when the run was killed.
#
#   ./rerun-failed-trials.sh                       # default: the gufo job
#   ./rerun-failed-trials.sh jobs/<other-job-dir>  # another job
#
# What it does:
#   1. preflight: pier not running, litellm pin present in pier, relay up,
#      model answers a real chat completion
#   2. moves every trial whose agent log contains the mcp error into
#      <job>/.infra-failed-backup/   (evidence preserved; task re-queues)
#   3. deletes empty/corrupt trial result.json left by the kill
#      (Pier auto-cleans such dirs and re-runs those tasks)
#   4. launches `pier job resume` detached with the container-reachable
#      base URL, then verifies it started cleanly
set -euo pipefail

REPO="/home/ugo/projects/deepswe-test"
JOB="${1:-jobs/deepswe-gufo-qwen3.8-flash-next-tp2-q8}"
case "$JOB" in /*) ;; *) JOB="$REPO/$JOB" ;; esac
MCP_MARKER="No module named 'mcp'"
PIER_MSA="/home/ugo/.local/share/uv/tools/datacurve-pier/lib/python3.13/site-packages/pier/agents/installed/mini_swe_agent.py"
LOG="$REPO/resume.log"

die() { echo "ERROR: $*" >&2; exit 1; }

cd "$REPO"

# ---------- 1. preflight ----------
[[ -f "$JOB/config.json" ]] || die "not a job dir: $JOB"
pgrep -f "bin/python .*pier (run|job resume)" >/dev/null && die "a pier job is already running - stop it first"
grep -q 'litellm==1.105.1' "$PIER_MSA" 2>/dev/null \
  || die "litellm pin missing from pier ($PIER_MSA) - reapply it or every new trial fails again"
docker ps --format '{{.Names}}' | grep -q '^deepswe-relay$' \
  || die "deepswe-relay container is down (see README §3.2)"
echo -n "model endpoint: "
WARM=$(curl -s -m 300 -o /dev/null -w '%{http_code}' http://127.0.0.1:4000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"gufo-qwen3.8-flash-next-tp2-q8","messages":[{"role":"user","content":"ping"}],"max_tokens":1}')
[[ "$WARM" == "200" ]] || die "model warm-up failed (HTTP $WARM)"
echo "OK"
FREE_GB=$(df -BG --output=avail "$REPO" | tail -1 | tr -dc '0-9')
[[ "$FREE_GB" -ge 60 ]] || echo "WARNING: only ${FREE_GB}G free disk" >&2

# ---------- 2. quarantine mcp-broken trials ----------
BACKUP="$JOB/.infra-failed-backup"
mkdir -p "$BACKUP"
n_moved=0
while IFS= read -r log; do
  d=$(dirname "$(dirname "$log")")
  echo "  quarantining (litellm 1.106.0 poisoned): $(basename "$d")"
  mv "$d" "$BACKUP/"
  n_moved=$((n_moved + 1))
done < <(grep -rl "$MCP_MARKER" "$JOB"/*/agent/mini-swe-agent.txt 2>/dev/null || true)
echo "quarantined: $n_moved trial(s) -> ${BACKUP#"$REPO/"}/"

# ---------- 3. drop empty/corrupt trial results from the kill ----------
n_bad=0
for r in "$JOB"/*/result.json; do
  [[ -e "$r" ]] || continue
  if ! python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$r" 2>/dev/null; then
    echo "  removing corrupt result: $(basename "$(dirname "$r")")/result.json"
    rm -f "$r"
    n_bad=$((n_bad + 1))
  fi
done
echo "corrupt results removed: $n_bad (those trials re-run automatically)"

# ---------- 4. resume ----------
[[ -f "$LOG" ]] && mv -f "$LOG" "$LOG.prev"
export OPENAI_API_BASE=http://172.17.0.1/v1    # NOT 127.0.0.1 - unreachable from containers
export OPENAI_BASE_URL=http://172.17.0.1/v1
export OPENAI_API_KEY=sk-local

nohup pier job resume -p "$JOB" > "$LOG" 2>&1 &
PIER_PID=$!
echo "pier resume started (PID $PIER_PID), log: ${LOG#"$REPO/"}/"

sleep 15
if grep -q "Traceback" "$LOG" 2>/dev/null; then
  tail -20 "$LOG"
  die "resume crashed - see above (previous crash log kept in ${LOG}.prev)"
fi
if ! kill -0 "$PIER_PID" 2>/dev/null; then
  tail -20 "$LOG"
  die "resume exited immediately"
fi

echo
echo "running. Watch with:"
echo "  tail -f ${LOG#"$REPO/"}/"
echo "  ./scoreboard.sh $JOB"
echo
echo "kept (already graded) trials are unchanged; re-queued = mcp-broken + killed + pending."
