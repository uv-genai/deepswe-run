# DeepSWE Benchmark Runner (local LiteLLM models)

Runs the [DeepSWE](https://github.com/datacurve-ai/deep-swe) coding-agent benchmark
(113 long-horizon SWE tasks) against models served by the **local LiteLLM proxy**
on this machine (`http://localhost:4000/v1`), using
[Pier](https://github.com/datacurve-ai/pier) + `mini-swe-agent`.

`run_deepswe.sh` is the one-command entry point. Everything it needs is documented here.

---

## 1. How it works

Each DeepSWE task runs inside an isolated Docker container. The agent
(`mini-swe-agent`) inside that container must reach your local model server, but the
task sandboxes declare `network_mode = "no-network"`. Pier bridges the two with a
per-trial **squid egress proxy** that only allows outbound HTTP(S) on **ports 80/443**
to an allowlist derived from `OPENAI_BASE_URL`.

That is why a relay is needed: LiteLLM listens on **:4000**, which squid blocks. A tiny
socat container forwards host **:80 → 127.0.0.1:4000**, and the agent is pointed at the
host's docker bridge address on port 80.

Request path:

```
mini-swe-agent (in task container)
  → HTTP_PROXY → pier-egress-proxy (squid, per trial; allowlists host:80)
    → 172.17.0.1:80  (deepswe-relay container on the host)
      → 127.0.0.1:4000  (LiteLLM proxy)
        → llama-swap :8080  (systemd service; hot-swaps llama.cpp instances)
          → llama-server (loads the requested GGUF model on demand)
```

The LiteLLM proxy (`~/software/litellm/litellm_config.yaml`) maps benchmark-facing model
IDs (e.g. `gufo-qwen3.8-flash-next-tp2-q8`) to backend llama.cpp models. All models go through
the same proxy, so switching models requires no wiring changes — only the `--model`
argument changes.

---

## 2. Prerequisites

| Component | Purpose | Check |
|---|---|---|
| Docker + Compose v2 | task sandboxes, relay | `docker compose version` |
| `pier` ≥ 0.3.1 | Harbor-compatible eval runner | `pier --version` |
| LiteLLM proxy on :4000 | model routing | `curl -s localhost:4000/v1/models` |
| `llama-swap` on :8080 | llama.cpp model serving | `systemctl is-active llama-swap` |
| ≥250 GB free disk | full run: ~1.5–1.7 GB of images+build cache per task (see §4) | `df -h /` |
| ~40+ GB RAM | model (≈30 GB) + trial containers (8 GB each) | `free -g` |

Install Pier (once):

```bash
uv tool install datacurve-pier
```

Clone the benchmark (once):

```bash
git clone https://github.com/datacurve-ai/deep-swe.git   # → ./deep-swe
```

---

## 3. Host setup (once per machine)

### 3.1 Model backend

The LiteLLM proxy expects llama-swap on `:8080`. If it isn't running, every request
500s with `Connection error`:

```bash
sudo systemctl start llama-swap       # unit is enabled → survives reboots
systemctl status llama-swap           # verify
```

> **Known failure mode:** this unit has silently died before. If a run starts erroring
> with `litellm.InternalServerError ... Connection error`, this is the first thing to
> check. Confirm the endpoint end-to-end:
>
> ```bash
> curl -s localhost:4000/v1/chat/completions -H 'Content-Type: application/json' \
>   -d '{"model":"gufo-qwen3.8-flash-next-tp2-q8","messages":[{"role":"user","content":"ping"}],"max_tokens":1}'
> ```
> First request after a cold start takes a while — llama-swap loads the GGUF into RAM.

### 3.2 Port-80 relay

Squid in the trial sandboxes only allows ports 80/443, so expose LiteLLM on host :80:

```bash
docker run -d --name deepswe-relay --network host --restart unless-stopped \
  alpine/socat tcp-listen:80,reuseaddr,fork tcp:127.0.0.1:4000
```

(If something else already owns host port 80 — e.g. a web server — change the
left side to another *Safe* port like `tcp-listen:443,...` and edit the port in
`.env` and `run_deepswe.sh` accordingly. Ports 80/443 are the only ones squid
will pass.)

### 3.3 Name resolution pin (required)

The LiteLLM proxy reaches its backends via `system76.local`. mDNS resolution of that
name is **unstable on this host** — lookups intermittently return unreachable IPv6
addresses — which makes the proxy 500 with `[Errno 111] Connection refused` on chat
completions (`/v1/models` still works, so this failure is easy to miss in a preflight).
Pin the name on the host so the proxy always dials a working address:

```bash
# put 'files' FIRST for .local names…
sudo sed -i 's/^hosts: mymachines mdns4_minimal/hosts: files mymachines mdns4_minimal/' /etc/nsswitch.conf
# …and pin the name (backup: /etc/hosts.bak-deepswe)
echo "127.0.0.1 system76.local" | sudo tee -a /etc/hosts
getent hosts system76.local   # must print 127.0.0.1, every time
```

Verify with real chat completions (not just `/v1/models`):

```bash
for i in 1 2 3; do
  curl -s -o /dev/null -w "chat#$i -> %{http_code}\n" -m 120 \
    http://127.0.0.1:4000/v1/chat/completions -H 'Content-Type: application/json' \
    -d '{"model":"gufo-qwen3.8-flash-next-tp2-q8","messages":[{"role":"user","content":"ping"}],"max_tokens":1}'
done   # must be 200,200,200
```

### 3.4 Environment file

`/home/ugo/projects/deepswe-test/.env`:

```
OPENAI_API_BASE=http://172.17.0.1/v1
OPENAI_BASE_URL=http://172.17.0.1/v1
OPENAI_API_KEY=sk-local
```

- `172.17.0.1` is the docker0 bridge gateway — the address trial containers and the
  squid proxy use to reach this host. It is *not* `localhost` (that would resolve to
  inside the container).
- The API key is a placeholder; LiteLLM here doesn't authenticate.

### 3.5 Pin litellm in Pier (required after every pier upgrade)

Pier installs the agent with a bare `uv tool install mini-swe-agent` inside **every
trial image build**, so the agent's `litellm` dependency always resolves to whatever
version is newest on PyPI at build time. On **2026-10-18, litellm 1.106.0** was
released (13:49 local) with a broken optional import — every trial image built after
that died within minutes:

```
litellm.APIConnectionError: OpenAIException - No module named 'mcp'.
Retrying <unknown> in 4/8/16/32/60 seconds ...  (then the agent gives up)
```

The verifier then grades an **empty patch → reward 0, f2p 0/total** for every
affected trial (22 trials were zeroed before the run was stopped — the model was
never at fault). Working images (built before the release) carry `litellm 1.105.1`.

**The fix** — pin the dependency in Pier's install spec (applied in this setup):

```bash
# file: <pier>/site-packages/pier/agents/installed/mini_swe_agent.py  (line ~653)
uv tool install mini-swe-agent{version_spec} --with "litellm==1.105.1"
```

- The install spec is hashed into the agent-install fingerprint, so a changed pin
  forces a **fresh image build** — no stale cache can reintroduce the bad version.
- The pin only affects trials built *after* it is applied; running trials keep the
  code they started with.
- **`uv tool upgrade datacurve-pier` reinstalls the package files and silently
  wipes this edit.** After any pier upgrade, before any run:

```bash
./scripts/reapply-litellm-pin.sh     # idempotent; verifies the edit parses; fails safe
```

  Both `run_deepswe.sh` (warm-up) and `rerun-failed-trials.sh` (preflight) abort
  early if the pin is missing, so the failure mode is caught before trials start.

If a future pier release restructures that install command, the reapply script
detects it and prints the candidate lines instead of guessing — apply the
`--with "litellm==1.105.1"` addition manually in that case.

---

## 4. Running benchmarks

### With the wrapper script (recommended)

```bash
cd /home/ugo/projects/deepswe-test

./scripts/run_deepswe.sh --list                     # models available on the proxy
./scripts/run_deepswe.sh gufo-qwen3.8-flash-next-tp2-q8     # full 113-task run
```

Script flags:

| Flag | Meaning | Default |
|---|---|---|
| `--list` | list models served by the proxy, exit | — |
| `-l, --n-tasks N` | deterministic sample of N tasks | all 113 |
| `-s, --seed N` | sampling seed (with `--n-tasks`) | 0 |
| `-t, --task ID` | run a single task (directory name under `deep-swe/tasks/`) | — |
| `-n, --n-concurrent N`, `--concurrency N` | parallel trials | 3 |
| `-j, --job-name NAME` | explicit job name (must not already exist in `jobs/`) | derived from model/task |
| `-c, --config FILE` | inject a mini-swe agent YAML (e.g. `commit-incremental.yaml`) via `--ak config_yaml=…`; with no `-j` the job name gets `-cfg-<basename>` | **stock** mini-swe config |
| `-d, --dry` | print the exact `pier` command and exit (no warm-up, no launch) | — |
| `-w, --no-warmup` | skip the warm-up request that loads the model | warm up |
| `-h, --help` | usage | — |

The script **preflights** everything (llama-swap active, relay container up, proxy
answering, requested model actually served, disk space), **warms up** the model so
trial 1 doesn't burn budget on GGUF loading, then launches Pier. Non-interactive use
auto-detaches; for a run you want to survive terminal close:

```bash
nohup ./scripts/run_deepswe.sh gufo-qwen3.8-flash-next-tp2-q8 -n 2 > log/launcher.log 2>&1 &
```

Each model gets its own job namespace: log `log/deepswe-<model>.log`, results under
`jobs/deepswe-<model>/`, so runs for different models never clobber each other.

**Recommended first run:** a pilot —
`./scripts/run_deepswe.sh gufo-qwen3.8-flash-next-tp2-q8 -l 5 --seed 0`.

### Concurrency guidance

Every trial container is capped at 8 GB; the local 35B model needs ~30 GB. On this
machine (62 GB RAM): **2–3** is the sane range for the 35B models; **4+** only for the
small ones (`system76/qwen3.8-distilled-9b-q4`, `system76/bonsai-2-27b`).

Note: concurrency raises *task* throughput, not *token* throughput — all trials share
one llama.cpp instance. Higher concurrency mainly hides tool-execution/verifier time
behind model generation.

### Disk space budget & reclamation

Measured on this machine: each task costs **~1.5–1.7 GB** of Docker images + build
cache (agent image ~1 GB content, a separate verifier image, a ~76 MB per-trial squid
image, ~2.4 GB build-cache growth; tasks share base layers from the common ECR image).
Job results/trajectories are negligible (<10 MB/trial).

| Run | Disk needed |
|---|---|
| Single task / pilot (5 tasks) | ~10 GB |
| Full 113-task corpus, from scratch | **~180 GB peak → keep ≥250 GB free** |
| Resumed job, N trials remaining | N × ~1.7 GB |

⚠️ Pier's `--delete` removes trial **containers**, not **images** — per-trial images
accumulate monotonically for the whole job. A full run that starts with too little
free disk dies near the end with `no space left on device` (containers crash,
`result.json` files get truncated to 0 bytes, and a later `pier job resume` fails to
parse them — see §6).

**Reclaim after any job finishes** (returns ~80% of the footprint):

```bash
# 1. remove per-trial images (safe: skips images still used by containers)
docker ps -a --format '{{.Image}}' | sed 's/[^:]$/&:latest/' | sort -u > /tmp/keep.txt
docker images --format '{{.Repository}}:{{.Tag}}' \
  | grep -E '(-main|-pier-egress-proxy|__verifier__trial-main):latest$' \
  | grep -vxFf /tmp/keep.txt | xargs -r docker rmi

# 2. cap the build cache (keep the last 30 GB of layers)
docker builder prune -f --keep-storage 30GB
```

**Orphaned containers** from a crashed run keep running (and hold their images)
unless Pier shut down cleanly — check for trial containers whose job is no longer
running and `docker rm` them; they waste RAM and block image deletion.

### Manual invocation (no wrapper)

```bash
cd /home/ugo/projects/deepswe-test
set -a; source .env; set +a
nohup pier run -p deep-swe/tasks \
  --agent mini-swe-agent \
  --model openai/<model-id-from-proxy> \
  --env-file .env \
  --job-name deepswe-<model-id> \
  --n-concurrent 3 \
  -y > log/deepswe-<model-id>.log 2>&1 &
```

Task timeouts are generous: 3 h agent + 30 min verifier + 30 min build per task. A
full local-model run takes **multiple days**.

---

## 5. Monitoring & results

```bash
tail -f log/deepswe-<model>.log     # live job log
./scripts/scoreboard.sh                  # live scoreboard (newest job; auto-refresh 30s)
./scripts/scoreboard.sh jobs/<job-name>  # specific job
pier view jobs                  # web UI over all job trajectories (127.0.0.1:8080+)
```

`scoreboard.sh` reads each trial's `verifier/reward.json` as it lands, so it shows
the **running solve rate** (solved/graded, mean partial credit), a per-task table,
and what's in flight — Pier itself only prints the reward table after the whole job
finishes. It exits automatically when the job completes.

Per-trial outputs land in `jobs/<job-name>/<task>__<id>/`:

```
verifier/reward.json       score (see schema below)      ← the score
verifier/ctrf.json         machine-readable test report
verifier/test-stdout.txt   raw suite output + failure reasons
agent/mini-swe-agent.txt   full agent transcript
agent/trajectory.json      ATIF trajectory (for pier view / pier critique)
```

`reward.json` schema (written by the shared DeepSWE grader):

- `reward` — **binary 0/1**: 1 iff every fail-to-pass test passes *and* no
  pass-to-pass test regressed
- `f2p_total` / `f2p_passed`, `p2p_total` / `p2p_passed` — raw counts
- `f2p`, `p2p`, `partial` — pass fractions (for ranking/tie-breaking)
- `apply_failed` — set to 1 if the agent's patch didn't apply (auto reward 0)

Job-level rollup: `jobs/<job-name>/result.json` (completed/errored trials, token
counts). Summarize results across tasks:

```bash
# mean reward (the benchmark score) + mean partial credit
jq -s '{n: length,
       reward: (map(.reward) | add / length),
       partial: (map(.partial) | add / length),
       apply_failed: (map(select(.apply_failed == 1)) | length)}' \
  jobs/<job-name>/*/verifier/reward.json

# per-task table
for f in jobs/<job-name>/*/verifier/reward.json; do
  printf '%-55s %s\n' "$(basename $(dirname $(dirname $f)))" "$(jq -r '.reward' $f)"
done
```

---

## 6. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Agent log fills with `litellm.APIConnectionError ... No module named 'mcp'`, trials finish in ~5 min with reward 0 / f2p 0 | unpinned litellm resolved to a broken release at image build (e.g. 1.106.0) — **not** a model failure | `./scripts/reapply-litellm-pin.sh` (§3.5), then re-run the affected trials with `./scripts/rerun-failed-trials.sh` |
| After `uv tool upgrade datacurve-pier`, new trials fail with the mcp error | upgrade wiped the litellm pin | `./scripts/reapply-litellm-pin.sh` (§3.5) |
| Trials die mid-run; dockerd logs `no space left on device` | disk full — images + build cache accumulate ~1.7 GB/task | reclaim (§4 "Disk space"), resume the job |
| `pier job resume` crashes: `ValidationError ... EOF while parsing a value` | disk-full crash left 0-byte `result.json` files | `rm` the empty `*/result.json` files, then resume (trials re-run) |
| All trials error `NonZeroAgentExitCodeError`; agent log ends in `litellm.InternalServerError ... [Errno 111] Connection refused` | proxy's backend name resolves to a dead address (mDNS flake) — `/v1/models` still 200s, so preflight passes | pin `system76.local` (§3.3), re-run |
| All LLM calls fail: `litellm.InternalServerError ... Connection error` | LiteLLM proxy's backend on :8080 not running | `systemctl start llama-swap` |
| Script aborts: `deepswe-relay container is down` | relay missing | recreate it (§3.2) |
| Script aborts: `model '...' not served` | typo or model removed from LiteLLM config | `./scripts/run_deepswe.sh --list` |
| Image pulls fail mid-run | disk full (images are multi-GB) | `docker system df`; `docker system prune` |
| Trials hang / OOM kills | concurrency too high for RAM | lower `-n`; check `free -g`, `docker stats` |
| Verifier errors about network | expected — verifiers run with `no-network`; only the agent needs the proxy | — |
| Warm-up times out | cold GGUF load > 10 min, or backend overloaded | rerun; the model stays loaded once warm |
| Want to change model between runs | nothing to rewire — same proxy | just pass a different model to `run_deepswe.sh` |

Upstream task/verifier issues belong to
[datacurve-ai/deep-swe](https://github.com/datacurve-ai/deep-swe); runner issues to
[datacurve-ai/pier](https://github.com/datacurve-ai/pier).

---

## 7. Files in this directory

```
scripts/                    all runnable scripts (invoke from the repo root):
  run_deepswe.sh              benchmark launcher (preflight + warm-up + pier run)
  scoreboard.sh               live results viewer for a running job
  rerun-subset.sh             engine for subset batches (zeros/nearmiss/failed13/wallvictims/failed23;
                              MODEL=<id> targets another model, e.g. the maya campaign)
  rerun-zeros.sh              thin wrappers -> rerun-subset.sh
  rerun-nearmiss.sh             "
  rerun-failed13.sh             "  (forces --incremental)
  rerun-wallvictims.sh          "  (forces --incremental)
  rerun-failed-trials.sh      quarantine mcp-poisoned trials + resume the job
  start-rerun.sh              detached launcher -> rerun-failed-trials.sh
  reapply-litellm-pin.sh      re-pin litellm after a pier upgrade (§3.5)
  free-space.sh               reclaim per-trial docker images + build cache
  resume.sh                   one-off: resume the interrupted gufo job
  run-deepswe-miny.py         helper: generate deepswe-mini test cases
log/                      every run/batch log (gitignored): job logs
                         deepswe-<model>[-batch].log, launch logs *-start.log,
                         resume.log (+ .prev), tunnel logs
.env                     base-URL/API-key env passed to pier
deep-swe/                benchmark corpus (113 tasks), cloned from GitHub
commit-incremental.yaml  agent config with commit-mandate (used via --incremental)
jobs/                    per-job results (pier output); .infra-failed-backup/
                         inside a job holds quarantined infra-failed trials
reports/                 analysis + final report (results of record)
HANDOFF-*.md             session-restart handoff (dated snapshot)
```

> Layout note (2026-10-26): scripts were moved from the repo root into
> `scripts/` and all run logs into `log/`. Paths inside every script, this
> README, and the launch/watch instructions were updated accordingly; the
> dated `HANDOFF-*.md` still shows the old layout.
