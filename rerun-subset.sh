#!/usr/bin/env bash
# Engine for the post-completion re-runs: launches a NEW pier job over a task
# subset computed from the finished main job.
#
#   ./rerun-subset.sh zeros        [-n N] [--dry] [--incremental]
#   ./rerun-subset.sh nearmiss     [-n N] [--dry] [--incremental]
#   ./rerun-subset.sh failed13     [-n N] [--dry] [--incremental]
#   ./rerun-subset.sh wallvictims  [-n N] [--dry] [--incremental]
#
#   zeros       reward=0 and f2p < 50%   (includes the ungraded verifier-timeout task)
#   nearmiss    reward=0 and f2p >= 50%
#   failed13    the 13 remaining zeros of the zeros-rerun job
#   wallvictims the 6 tasks that died on the 262144-token context wall
#               (HANDOFF-20261024-1902.md §5; static list). Reruns only the ones
#               that are still unsolved AND show progress: latest attempt
#               f2p >= 0.5 (solved dropped; zeros like wasmi dropped)
#   -n N      concurrent trials (default 1 = strictly serial model requests)
#   --dry     compute + print everything, do not launch
#   --incremental  inject commit-incremental.yaml (commit after each feature;
#                  otherwise discarded-at-submit work scores zero - see
#                  reports/zeros-rerun-analysis-2026-10-21.md)
#   MODEL=... override the model (default gufo-qwen3.8-flash-next-tp2-q8)
#
#   --tag T     append -T to the job name (e.g. --tag r2 -> ...-inc-r2),
#               needed to rerun a group whose previous job dir already exists
#
# Normally invoked via the thin wrappers rerun-zeros.sh / rerun-nearmiss.sh /
# rerun-failed13.sh / rerun-wallvictims.sh.
set -euo pipefail

REPO="/home/ugo/projects/deepswe-test"
MAIN="$REPO/jobs/deepswe-gufo-qwen3.8-flash-next-tp2-q8"
MODEL="${MODEL:-gufo-qwen3.8-flash-next-tp2-q8}"
PIER_MSA="/home/ugo/.local/share/uv/tools/datacurve-pier/lib/python3.13/site-packages/pier/agents/installed/mini_swe_agent.py"
MODEL_SLUG="${MODEL//\//_}"

die() { echo "ERROR: $*" >&2; exit 1; }

GROUP="${1:-}"; [[ -n "$GROUP" ]] || die "usage: $0 zeros|nearmiss|failed13|wallvictims [-n N] [--dry] [--incremental] [--tag T]"; shift || true
N_CONC=1; DRY=0; INCR=0; TAG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--n-concurrent) N_CONC="$2"; shift 2 ;;
    --dry) DRY=1; shift ;;
    --incremental) INCR=1; shift ;;
    --tag) TAG="$2"; shift 2 ;;
    *) die "unknown argument: $1" ;;
  esac
done
[[ "$GROUP" == "zeros" || "$GROUP" == "nearmiss" || "$GROUP" == "failed13" || "$GROUP" == "wallvictims" ]] \
  || die "group must be zeros, nearmiss, failed13 or wallvictims"
[[ "$N_CONC" =~ ^[0-9]+$ && "$N_CONC" -ge 1 ]] || die "invalid -n: $N_CONC"
[[ -f "$MAIN/result.json" ]] || die "main job not found: $MAIN"

[[ "$TAG" =~ ^[A-Za-z0-9._-]+$ ]] || { [[ -z "$TAG" ]] || die "invalid --tag: $TAG"; }
JOB_NAME="deepswe-${MODEL_SLUG}-${GROUP}-rerun"
[[ "$INCR" == "1" ]] && JOB_NAME+="-inc"
[[ -n "$TAG" ]] && JOB_NAME+="-$TAG"
LOG="$REPO/${JOB_NAME}.log"
cd "$REPO"

if [[ "$INCR" == "1" && ! -f "$REPO/commit-incremental.yaml" ]]; then
  die "commit-incremental.yaml not found in $REPO"
fi

# ---------- compute task list ----------
if [[ "$GROUP" == "wallvictims" ]]; then
  # static list from HANDOFF §5 (context-wall victims), latest-attempt aware:
  #   solved (reward=1)          -> drop
  #   latest f2p < 0.5           -> drop (no progress yet, e.g. wasmi)
  #   never graded               -> keep
  mapfile -t TASKS < <(python3 - "$MODEL_SLUG" "$REPO/jobs" <<'PYEOF'
import json, glob, os, sys
model_slug, jobs_dir = sys.argv[1], sys.argv[2]
WALL = [
    'gql-incremental-graphql-delivery',
    'ink-grid-box-layout',
    'kea-atomic-signal-selectors',
    'koota-composite-trait-aspects',
    'sqlfmt-create-table-ddl-formatting',
    'wasmi-trap-coredumps',
]
# latest attempt per slug across every same-model job
latest = {}   # slug -> (mtime, reward, f2p|None)
for rw in glob.glob(os.path.join(jobs_dir, f'deepswe-{model_slug}*/', '*/verifier/reward.json')):
    if '/.infra-failed-backup/' in rw: continue
    try:
        d = os.path.dirname(os.path.dirname(rw))
        slug = os.path.basename(json.load(open(d + '/config.json'))['task']['path'].rstrip('/'))
        v = json.load(open(rw)); m = os.path.getmtime(rw)
        if slug not in latest or m > latest[slug][0]:
            latest[slug] = (m, v.get('reward', 0), v.get('f2p', 0.0))
    except Exception: pass
sel = []
for s in WALL:
    if s not in latest:
        sel.append(s); continue          # never graded -> run
    m, r, f = latest[s]
    if r == 1: continue                  # solved already
    if f is not None and f < 0.5: continue   # still zero progress
    sel.append(s)
print('\n'.join(sel))
PYEOF
  )
elif [[ "$GROUP" == "failed13" ]]; then
  SOURCE_JOB="$REPO/jobs/deepswe-gufo-qwen3.8-flash-next-tp2-q8-zeros-rerun"
  [[ -d "$SOURCE_JOB" ]] || die "zeros-rerun job not found: $SOURCE_JOB"
  mapfile -t TASKS < <(python3 - "$SOURCE_JOB" "$MODEL_SLUG" <<'PYEOF'
import json, glob, os, sys
src, model_slug = sys.argv[1], sys.argv[2]
sel = []
for d in sorted(glob.glob(src + '/*/')):
    if '.infra' in d: continue
    rw = d + 'verifier/reward.json'
    if not (os.path.exists(rw) and json.load(open(rw)).get('reward') == 0): continue
    try: slug = os.path.basename(json.load(open(d + 'config.json'))['task']['path'].rstrip('/'))
    except Exception: continue
    sel.append(slug)
# solved-elsewhere guard: same-model job that already scored reward=1 for this task
solved = set()
for rw in glob.glob(os.path.join(os.path.dirname(src), f'deepswe-{model_slug}*/', '*/verifier/reward.json')):
    if '/.infra-failed-backup/' in rw: continue
    try:
        if json.load(open(rw)).get('reward') == 1:
            solved.add(os.path.basename(json.load(open(os.path.dirname(os.path.dirname(rw)) + '/config.json'))['task']['path'].rstrip('/')))
    except Exception: pass
print('\n'.join(sorted(set(sel) - solved)))
PYEOF
  )
else
  mapfile -t TASKS < <(python3 - "$MAIN" "$GROUP" "$MODEL_SLUG" <<'PYEOF'
import json, glob, os, sys
main, group, model_slug = sys.argv[1], sys.argv[2], sys.argv[3]
# Latest attempt per task across MAIN + every same-model job: reruns change scores
# (solved tasks drop out of re-run lists; new near-misses drop in).
latest = {}   # slug -> (mtime, reward, f2p|None)
for rw in glob.glob(os.path.join(os.path.dirname(main), f'deepswe-{model_slug}*/', '*/verifier/reward.json')):
    if '/.infra-failed-backup/' in rw: continue
    try:
        d = os.path.dirname(os.path.dirname(rw))
        slug = os.path.basename(json.load(open(d + '/config.json'))['task']['path'].rstrip('/'))
        v = json.load(open(rw)); m = os.path.getmtime(rw)
        if slug not in latest or m > latest[slug][0]:
            latest[slug] = (m, v.get('reward', 0), v.get('f2p', 0.0))
    except Exception: pass
# never-graded tasks (should be none after the full corpus): treat as ungraded zeros
for d in sorted(glob.glob(main + '/*/')):
    if '.infra' in d or os.path.exists(d + 'verifier/reward.json'): continue
    try:
        slug = os.path.basename(json.load(open(d + 'config.json'))['task']['path'].rstrip('/'))
        latest.setdefault(slug, (0, 0, None))
    except Exception: pass
sel = sorted(s for s, (m, r, f) in latest.items()
             if r == 0 and ((f is None or f < 0.5) if group == 'zeros' else (f is not None and f >= 0.5)))
print('\n'.join(sel))
PYEOF
)
fi
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
[[ "$INCR" == "1" ]] && CMD+=(--ak "config_yaml=$(cat "$REPO/commit-incremental.yaml")")
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
[[ "$INCR" == "1" ]] && echo "(commit-incremental config active: first trial's log header should show custom.yaml in the config specs)"
