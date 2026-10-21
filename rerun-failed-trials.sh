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

#   ./rerun-failed-trials.sh [job-dir] [-n N]
#
#   -n N   set trial concurrency to N before resuming (Pier has no -n on
#          resume; both config.json and lock.json must be changed together or
#          the resume lock check fails). N trials = at most N simultaneous
#          model requests (modulo client retries).
set -euo pipefail

REPO="/home/ugo/projects/deepswe-test"
JOB=""
N_CONC=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--n-concurrent) N_CONC="$2"; shift 2 ;;
    -*) die_flag() { echo "ERROR: unknown flag: $1" >&2; exit 1; }; die_flag "$1" ;;
    *) JOB="$1"; shift ;;
  esac
done
JOB="${JOB:-jobs/deepswe-gufo-qwen3.8-flash-next-tp2-q8}"
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
  || die "litellm pin missing from pier ($PIER_MSA) - run ./reapply-litellm-pin.sh first (README §3.5)"

# reclaim leaked trial networks: pkill'ing pier skips compose down, and Docker's
# address pools are finite -> 'all predefined address pools have been fully subnetted'
n_net=0
while read -r id name; do
  [[ "$name" =~ __[a-z0-9]{7}(_|$) ]] || continue
  c=$(docker network inspect -f '{{len .Containers}}' "$id" 2>/dev/null || echo -1)
  if [[ "$c" == "0" ]]; then
    docker network rm "$id" >/dev/null 2>&1 && n_net=$((n_net+1)) && echo "  reclaimed leaked network: $name"
  fi
done < <(docker network ls --format '{{.ID}} {{.Name}}')
echo "leaked trial networks reclaimed: $n_net"
docker network create "__pool-probe" >/dev/null 2>&1 \
  && docker network rm "__pool-probe" >/dev/null \
  || die "docker address pool still exhausted - remove orphan networks: docker network ls"
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

# ---------- 2b. quarantine infra-errored trials ----------
# These have a result.json (resume treats them as DONE), but the failure is
# infrastructure, not a model outcome. Evidence-based rules:
#   - RuntimeError                                  -> docker/pier infra (always)
#   - NonZeroAgentExit/AgentTimeout + reward 0 +
#     InternalServerError markers in the agent log   -> died in a proxy 500 storm
#   - errored but reward 1 (solved despite exception) -> NEVER touch
#   - errored, reward 0, no 500s                      -> genuine failure/timeout;
#                                                       left for the end-of-run review
n_rt=0
mapfile -t RT_RESULTS < <(find "$JOB" -mindepth 2 -maxdepth 2 -name result.json -not -path "*/.infra-failed-backup/*" | sort)
for r in "${RT_RESULTS[@]}"; do
  et=$(python3 -c "import json,sys;print(((json.load(open(sys.argv[1])).get('exception_info') or {}).get('exception_type') or ''))" "$r" 2>/dev/null || echo "")
  [[ -n "$et" ]] || continue
  d=$(dirname "$r")
  keep=0
  if [[ "$et" == "RuntimeError" ]]; then
    keep=1
  elif [[ "$et" == "NonZeroAgentExitCodeError" || "$et" == "AgentTimeoutError" ]]; then
    reward=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get('reward'))" "$d/verifier/reward.json" 2>/dev/null || echo none)
    if [[ "$reward" == "0" ]] && grep -q "InternalServerError" "$d/agent/mini-swe-agent.txt" 2>/dev/null; then
      keep=1
    fi
  fi
  if [[ "$keep" == "1" ]]; then
    echo "  quarantined ($et): $(basename "$d")"
    mv "$d" "$BACKUP/"
    n_rt=$((n_rt + 1))
  fi
done
echo "infra-errored trials quarantined: $n_rt"

# ---------- 2c. set trial concurrency (config.json + lock.json must agree) ----------
if [[ -n "$N_CONC" ]]; then
  [[ "$N_CONC" =~ ^[0-9]+$ && "$N_CONC" -ge 1 ]] || die "invalid -n value: $N_CONC"
  python3 - "$JOB" "$N_CONC" <<'PY'
import json, sys
job, n = sys.argv[1], int(sys.argv[2])
for name in ("config.json", "lock.json"):
    p = f"{job}/{name}"
    try:
        data = json.load(open(p))
    except Exception as e:
        sys.exit(f"cannot parse {p}: {e}")
    old = data.get("n_concurrent_trials")
    if old != n:
        data["n_concurrent_trials"] = n
        with open(p, "w") as fh:
            json.dump(data, fh, indent=4)
        print(f"  concurrency {name}: {old} -> {n}")
    else:
        print(f"  concurrency {name}: {n} (unchanged)")
PY
  # both files must still be valid JSON after the edit
  python3 -c "import json,sys; [json.load(open(f)) for f in (sys.argv[1]+'/config.json', sys.argv[1]+'/lock.json')]" "$JOB" \
    || die "config/lock edit left invalid JSON - restore from .prev if needed"
fi

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
