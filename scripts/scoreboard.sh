#!/usr/bin/env bash
# Live scoreboard for a running (or finished) DeepSWE pier job.
#
#   ./scripts/scoreboard.sh                              # newest job in jobs/
#   ./scripts/scoreboard.sh jobs/deepswe-gufo-...        # specific job dir
#   ./scripts/scoreboard.sh jobs/deepswe-gufo-... -n 10  # refresh every 10s (default 30)
set -euo pipefail

JOB="${1:-}"
REFRESH=30
# allow flags in any position
ARGS=()
for a in "$@"; do
  case "$a" in
    -n) ;;
    -*) ;;
    *) ARGS+=("$a") ;;
  esac
done
[[ $# -ge 2 && "$1" != -* && "$2" == "-n" ]] && REFRESH="$3"
[[ -z "$JOB" ]] && JOB=$(ls -td "$(dirname "$0")"/../jobs/*/ 2>/dev/null | head -1)
JOB="${JOB%/}"
[[ -f "$JOB/result.json" ]] || { echo "no result.json in $JOB" >&2; exit 1; }

draw() {
  clear
  python3 - "$JOB" <<'EOF'
import json, glob, os, sys, time
job = sys.argv[1]

# finished/errored counters refresh only at job end; derive live state from trial dirs
n_graded = 0; solved = 0; partial_sum = 0.0; rows = []
for f in glob.glob(os.path.join(job, "*/verifier/reward.json")):
    try:
        v = json.load(open(f))
    except (json.JSONDecodeError, OSError):
        continue
    task = os.path.basename(os.path.dirname(os.path.dirname(f)))
    n_graded += 1
    solved += int(v.get("reward", 0))
    partial_sum += float(v.get("partial", 0.0))
    rows.append((task, v.get("reward", 0), v.get("f2p_passed", 0), v.get("f2p_total", 0),
                 round(float(v.get("partial", 0.0)), 3)))

# trials in flight (have a dir + agent log, no reward yet)
inflight = []
for d in glob.glob(os.path.join(job, "*/")):
    if os.path.exists(os.path.join(d, "verifier/reward.json")):
        continue
    log = os.path.join(d, "agent", "mini-swe-agent.txt")
    if os.path.exists(log):
        age = int((time.time() - os.path.getmtime(log)) / 60)
        inflight.append((os.path.basename(d.rstrip("/")), os.path.getsize(log) // 1024, age))

model = "?"
try:
    lock = json.load(open(os.path.join(job, "lock.json")))
    inv = lock.get("invocation", [])
    if "--model" in inv:
        model = inv[inv.index("--model") + 1]
except Exception:
    pass
if model == "?":
    # resumed jobs record `pier job resume` as invocation; fall back to config
    try:
        cfg = json.load(open(os.path.join(job, "config.json")))
        model = cfg["agents"][0].get("model") or "?"
    except Exception:
        pass

print(f"job:    {os.path.basename(job)}")
print(f"model:  {model}")
print(f"score:  {solved}/{n_graded} solved ({solved/n_graded*100:.1f}%)" if n_graded else "score:  no graded trials yet")
if n_graded:
    print(f"partial credit (mean): {partial_sum/n_graded:.3f}")
print(f"in flight: {len(inflight)}   refreshed: {time.strftime('%H:%M:%S')}")
print()
if rows:
    print(f"{'task':46s} {'reward':>6s} {'f2p':>10s} {'partial':>8s}")
    for task, r, fp, ft, p in sorted(rows):
        print(f"{task[:46]:46s} {r:>6} {fp:>4}/{ft:<4} {p:>8}")
if inflight:
    print()
    print("running now:")
    for name, kb, idle in sorted(inflight):
        print(f"  {name[:44]:44s} log={kb:>5}KB  last activity {idle}m ago")
EOF
}

while true; do
  draw
  # stop looping once job is finished (result.json got a finish timestamp and nothing inflight)
  FINISHED=$(python3 -c "import json;print(json.load(open('$JOB/result.json')).get('finished_at') or '')")
  N_INFLIGHT=$(find "$JOB" -maxdepth 2 -name mini-swe-agent.txt -path "*/agent/*" | while read -r f; do d=$(dirname $(dirname "$f")); [ -f "$d/verifier/reward.json" ] || echo x; done | wc -l)
  if [ -n "$FINISHED" ] && [ "$N_INFLIGHT" -eq 0 ]; then
    echo; echo "job finished at $FINISHED — exiting (Ctrl-C earlier to keep watching)"
    exit 0
  fi
  sleep "$REFRESH"
done
