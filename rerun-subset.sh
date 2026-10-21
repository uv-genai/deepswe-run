#!/usr/bin/env bash
# Engine for the post-completion re-runs: launches a NEW pier job over a task
# subset computed from the finished main job.
#
#   ./rerun-subset.sh zeros     [-n N] [--dry]
#   ./rerun-subset.sh nearmiss  [-n N] [--dry]
#
#   zeros     reward=0 and f2p < 50%   (includes the ungraded verifier-timeout task)
#   nearmiss  reward=0 and f2p >= 50%
#   -n N      concurrent trials (default 1 = strictly serial model requests)
#   --dry     compute + print everything, do not launch
#   MODEL=... override the model (default gufo-qwen3.8-flash-next-tp2-q8)
#
# Normally invoked via the thin wrappers rerun-zeros.sh / rerun-nearmiss.sh.
set -euo pipefail

REPO="/home/ugo/projects/deepswe-test"
MAIN="$REPO/jobs/deepswe-gufo-qwen3.8-flash-next-tp2-q8"
MODEL="${MODEL:-gufo-qwen3.8-flash-next-tp2-q8}"
PIER_MSA="/home/ugo/.local/share/uv/tools/datacurve-pier/lib/python3.13/site-packages/pier/agents/installed/mini_swe_agent.py"
MODEL_SLUG="${MODEL//\//_}"

die() { echo "ERROR: $*" >&2; exit 1; }

GROUP="${1:-}"; [[ -n "$GROUP" ]] || die "usage: $0 zeros|nearmiss [-n N] [--dry]"; shift || true
N_CONC=1; DRY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--n-concurrent) N_CONC="$2"; shift 2 ;;
    --dry) DRY=1; shift ;;
    *) die "unknown argument: $1" ;;
  esac
done
[[ "$GROUP" == "zeros" || "$GROUP" == "nearmiss" ]] || die "group must be zeros or nearmiss"
[[ "$N_CONC" =~ ^[0-9]+$ && "$N_CONC" -ge 1 ]] || die "invalid -n: $N_CONC"
[[ -f "$MAIN/result.json" ]] || die "main job not found: $MAIN"

JOB_NAME="deepswe-${MODEL_SLUG}-${GROUP}-rerun"
LOG="$REPO/${JOB_NAME}.log"
cd "$REPO"

# ---------- compute task list from the finished main job ----------
mapfile -t TASKS < <(python3 - "$MAIN" "$GROUP" "$MODEL_SLUG" <<'PYEOF'
import json, glob, os, sys
main, group, model_slug = sys.argv[1], sys.argv[2], sys.argv[3]
tasks = {}
for d in sorted(glob.glob(main + '/*/')):
    if '.infra' in d: continue
    cfg = d + 'config.json'
    if not os.path.exists(cfg): continue
    try: slug = os.path.basename(json.load(open(cfg))['task']['path'].rstrip('/'))
    except Exception: continue
    rw = d + 'verifier/reward.json'
    if os.path.exists(rw):
        v = json.load(open(rw)); tasks[slug] = (v.get('reward', 0), v.get('f2p', 0.0))
    else:
        tasks[slug] = (0, None)   # ungraded (verifier timeout)
# solved anywhere in a same-model job (e.g. a standalone single-task run) is solved:
# exclude it so re-runs never duplicate recovered tasks
solved_elsewhere = set()
for rw in glob.glob(os.path.join(os.path.dirname(main), f'deepswe-{model_slug}*/', '*/verifier/reward.json')):
    if '/.infra-failed-backup/' in rw: continue
    try:
        if json.load(open(rw)).get('reward') == 1:
            d = os.path.dirname(os.path.dirname(rw))
            cfg = os.path.join(d, 'config.json')
            solved_elsewhere.add(os.path.basename(json.load(open(cfg))['task']['path'].rstrip('/')))
    except Exception: pass
sel = sorted(s for s, (r, f) in tasks.items()
             if r == 0 and s not in solved_elsewhere
             and ((f is None or f < 0.5) if group == 'zeros' else (f is not None and f >= 0.5)))
print('\n'.join(sel))
PYEOF
)
[[ ${#TASKS[@]} -ge 1 ]] || die "no tasks matched group '$GROUP'"
echo "group '$GROUP': ${#TASKS[@]} task(s):"
printf '  %s\n' "${TASKS[@]}"

[[ -d "jobs/$JOB_NAME" ]] && die "job dir jobs/$JOB_NAME already exists - remove/rename it first (protects previous results)"

# ---------- preflight ----------
pgrep -f "bin/python .*pier (run|job resume)" >/dev/null && die "a pier job is already running - wait for it (or let the sequential plan finish)"
grep -q 'litellm==1.105.1' "$PIER_MSA" 2>/dev/null \
  || die "litellm pin missing from pier - run ./reapply-litellm-pin.sh first (README §3.5)"
docker ps --format '{{.Names}}' | grep -q '^deepswe-relay$' || die "deepswe-relay container is down (README §3.2)"

# reclaim leaked trial networks + pool probe (pkill'd pier runs leak them)
n_net=0
while read -r id name; do
  [[ "$name" =~ __[a-z0-9]{7}(_|$) ]] || continue
  c=$(docker network inspect -f '{{len .Containers}}' "$id" 2>/dev/null || echo -1)
  if [[ "$c" == "0" ]]; then docker network rm "$id" >/dev/null 2>&1 && n_net=$((n_net+1)); fi
done < <(docker network ls --format '{{.ID}} {{.Name}}')
echo "leaked trial networks reclaimed: $n_net"
docker network create "__pool-probe" >/dev/null 2>&1 && docker network rm "__pool-probe" >/dev/null \
  || die "docker address pool still exhausted"

echo -n "model endpoint ($MODEL): "
WARM=$(curl -s -m 300 -o /dev/null -w '%{http_code}' http://127.0.0.1:4000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d "{\"model\":\"${MODEL}\",\"messages\":[{\"role\":\"user\",\"content\":\"ping\"}],\"max_tokens\":1}")
[[ "$WARM" == "200" ]] || die "model warm-up failed (HTTP $WARM) - fix the backend first"
echo "OK"

FREE_GB=$(df -BG --output=avail "$REPO" | tail -1 | tr -dc '0-9')
[[ "$FREE_GB" -ge 40 ]] || echo "WARNING: only ${FREE_GB}G free disk (each trial ~1.7G)" >&2

[[ "$DRY" == 1 ]] && { echo "--dry: nothing launched"; exit 0; }

# ---------- launch ----------
export OPENAI_API_BASE=http://172.17.0.1/v1    # NOT 127.0.0.1 - unreachable from containers
export OPENAI_BASE_URL=http://172.17.0.1/v1
export OPENAI_API_KEY=sk-local

CMD=(pier run -p "$REPO/deep-swe/tasks" --agent mini-swe-agent --model "openai/${MODEL}"
     --job-name "$JOB_NAME" --n-concurrent "$N_CONC" -y)
for t in "${TASKS[@]}"; do CMD+=(-i "$t"); done

echo; echo "running: ${CMD[*]}"
nohup "${CMD[@]}" > "$LOG" 2>&1 &
PIER_PID=$!
echo "pier started (PID $PIER_PID), log: ${LOG#"$REPO/"}/"
sleep 15
if grep -q "Traceback\|ValueError" "$LOG" 2>/dev/null || ! kill -0 "$PIER_PID" 2>/dev/null; then
  tail -20 "$LOG"; die "launch failed - see above"
fi
echo "running. Watch with:"
echo "  tail -f ${LOG#"$REPO/"}/"
echo "  ./scoreboard.sh jobs/$JOB_NAME"
