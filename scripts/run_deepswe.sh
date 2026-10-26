#!/usr/bin/env bash
# Run the DeepSWE benchmark against any model served by the local LiteLLM proxy.
#
# Usage:
#   ./scripts/run_deepswe.sh --list                      # list models available on the proxy
#   ./scripts/run_deepswe.sh gufo-qwen3.8-flash-next-tp2-q8      # full 113-task run
#   ./scripts/run_deepswe.sh gufo-qwen3.8-flash-next-tp2-q8 -l 5 --seed 0     # 5-task pilot
#   ./scripts/run_deepswe.sh gufo-qwen3.8-flash-next-tp2-q8 -n 2 -t bandit-incremental-cache-control
#   ./scripts/run_deepswe.sh gufo-qwen3.8-flash-next-tp2-q8 -j deepswe-...-leaderboard   # custom job name
#
# Flags:
#   --list            List models served by the proxy and exit
#   -l, --n-tasks N   Run at most N tasks (deterministic sample, default: all 113)
#   -n, --n-concurrent N, --concurrency N   Parallel trials (default: 3; each container capped at 8G)
#   -s, --seed N      Sampling seed for --n-tasks (default: 0)
#   -t, --task ID     Run a single task by directory name instead of the corpus
#   -j, --job-name NAME   Override the derived job name (jobs/NAME must not exist)
#   -w, --no-warmup   Skip the warm-up request that forces llama-swap to load the model
#   -h, --help        Show this help
set -euo pipefail

PROXY_BASE_HOST="http://127.0.0.1"   # host-side (preflight/warm-up only)
PROXY_CONTAINER="http://172.17.0.1" # docker0 gateway - the ONLY address trial containers can reach
PROXY_PORT=4000
PROXY_BASE="http://127.0.0.1:${PROXY_PORT}"
PROXY_BASE_HOST_PORT="${PROXY_BASE_HOST}/v1"     # port 80: what containers can reach through squid
REPO_DIR="/home/ugo/projects/deepswe-test"
TASKS_DIR="${REPO_DIR}/deep-swe/tasks"
WARMUP_TIMEOUT=600

die() { echo "ERROR: $*" >&2; exit 1; }

usage() { sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }

# ---------- args ----------
MODEL=""
LIST=0; N_TASKS=""; N_CONC=3; SEED=0; TASK=""; WARMUP=1; JOB_OVERRIDE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --list) LIST=1; shift ;;
    -l|--n-tasks) N_TASKS="$2"; shift 2 ;;
    -n|--n-concurrent|--concurrency) N_CONC="$2"; shift 2 ;;
    -s|--seed) SEED="$2"; shift 2 ;;
    -t|--task) TASK="$2"; shift 2 ;;
    -j|--job-name) JOB_OVERRIDE="$2"; shift 2 ;;
    -w|--no-warmup) WARMUP=0; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) die "unknown flag: $1 (see --help)" ;;
    *) [[ -n "$MODEL" ]] && die "unexpected argument: $1"; MODEL="$1"; shift ;;
  esac
done

# ---------- list models ----------
if [[ $LIST == 1 ]]; then
  curl -sf "${PROXY_BASE}/v1/models" \
    | python3 -c 'import json,sys; [print(m["id"]) for m in json.load(sys.stdin)["data"]]' \
    || die "cannot reach LiteLLM proxy at ${PROXY_BASE}"
  exit 0
fi

[[ -n "$MODEL" ]] || { usage; echo; die "model name is required (try: ./scripts/run_deepswe.sh --list)"; }
command -v pier >/dev/null || die "pier not on PATH (uv tool install datacurve-pier)"
MSA=$(ls -1 /home/ugo/.local/share/uv/tools/datacurve-pier/lib/python*/site-packages/pier/agents/installed/mini_swe_agent.py 2>/dev/null | head -1)
if [[ -n "$MSA" ]] && ! grep -q 'litellm==1.105.1' "$MSA"; then
  die "litellm pin missing from pier (upgraded?) - run: ./scripts/reapply-litellm-pin.sh (README §3.5)"
fi
[[ -d "$TASKS_DIR" ]] || die "tasks dir not found: $TASKS_DIR (git clone https://github.com/datacurve-ai/deep-swe.git)"

# ---------- prereq checks ----------
systemctl is-active --quiet llama-swap \
  || die "llama-swap backend is down - run: sudo systemctl start llama-swap"
docker ps --filter name=deepswe-relay --format '{{.Names}}' | grep -q deepswe-relay \
  || die "deepswe-relay container is down - see README notes; run:
  docker run -d --name deepswe-relay --network host --restart unless-stopped \
    alpine/socat tcp-listen:80,reuseaddr,fork tcp:127.0.0.1:4000"

curl -sf "${PROXY_BASE}/v1/models" >/dev/null \
  || die "LiteLLM proxy not answering at ${PROXY_BASE}"

curl -sf "${PROXY_BASE}/v1/models" | grep -q "\"id\":\"${MODEL}\"" \
  || die "model '${MODEL}' not served by the proxy. Available:
$("$(dirname "$0")/run_deepswe.sh" --list)"

FREE_GB=$(df -BG --output=avail "$REPO_DIR" | tail -1 | tr -dc '0-9')
[[ "${FREE_GB:-0}" -ge 40 ]] \
  || echo "WARNING: only ${FREE_GB}G free disk; image pulls may fail mid-run" >&2

# ---------- warm up (forces llama-swap to load this model) ----------
if [[ $WARMUP == 1 ]]; then
  echo "Warming up ${MODEL} (loading model into memory, up to ${WARMUP_TIMEOUT}s)..."
  code=$(curl -s -o /dev/null -w '%{http_code}' -m "$WARMUP_TIMEOUT" \
    "${PROXY_BASE_HOST_PORT}/chat/completions" -H 'Content-Type: application/json' \
    -d "{\"model\":\"${MODEL}\",\"messages\":[{\"role\":\"user\",\"content\":\"ping\"}],\"max_tokens\":1}")
  [[ "$code" == "200" ]] || die "warm-up request failed (HTTP $code) for ${MODEL}"
  echo "Model is live."
fi

# ---------- run config ----------
export OPENAI_API_BASE="${PROXY_CONTAINER}/v1"
export OPENAI_BASE_URL="${PROXY_CONTAINER}/v1"
export OPENAI_API_KEY=sk-local

MODEL_SLUG="${MODEL//\//_}"
JOB_NAME="deepswe-${MODEL_SLUG}"
[[ -n "$TASK" ]] && JOB_NAME="${JOB_NAME}-${TASK}"
[[ -n "$N_TASKS" ]] && JOB_NAME="${JOB_NAME}-n${N_TASKS}-s${SEED}"
[[ -n "$JOB_OVERRIDE" ]] && JOB_NAME="$JOB_OVERRIDE"
# never clobber an existing job (results of record live in jobs/<name>/)
if [[ -d "${REPO_DIR}/jobs/${JOB_NAME}" ]]; then
  die "jobs/${JOB_NAME} already exists - pick another -j name (protects previous results)"
fi

CMD=(pier run --agent mini-swe-agent --model "openai/${MODEL}"
     --job-name "$JOB_NAME" --n-concurrent "$N_CONC" -y)
if [[ -n "$TASK" ]]; then
  [[ -d "$TASKS_DIR/$TASK" ]] || die "unknown task: $TASK (ls $TASKS_DIR)"
  CMD+=(-p "$TASKS_DIR/$TASK")
else
  CMD+=(-p "$TASKS_DIR")
  [[ -n "$N_TASKS" ]] && CMD+=(--n-tasks "$N_TASKS" --sample-seed "$SEED")
fi

echo "Job:    $JOB_NAME"
echo "Model:  openai/${MODEL}"
echo "Tasks:  ${TASK:-${N_TASKS:-all 113}}${N_TASKS:+ (seed $SEED)}"
echo "Concurrent trials: $N_CONC"
echo "Log:    ${REPO_DIR}/log/${JOB_NAME}.log"
echo "Results:${REPO_DIR}/jobs/${JOB_NAME}/"
echo
echo "Running: ${CMD[*]}"
echo

cd "$REPO_DIR"
if [[ -t 0 && -t 1 ]]; then
  # interactive: run in foreground
  exec "${CMD[@]}"
else
  # nohup/background: detach with logs
  mkdir -p "${REPO_DIR}/log"
  nohup "${CMD[@]}" > "${REPO_DIR}/log/${JOB_NAME}.log" 2>&1 &
  PID=$!
  sleep 5
  kill -0 "$PID" 2>/dev/null || { tail -20 "${REPO_DIR}/log/${JOB_NAME}.log"; die "pier exited immediately"; }
  echo "Started (PID $PID). Follow with: tail -f log/${JOB_NAME}.log"
  echo "Inspect later with: pier view jobs"
fi
