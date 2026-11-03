# HANDOFF — DeepSWE Benchmark (live)

> **This file is live.** It is updated whenever results, config, or pending work
> change — treat it as the single source of truth for starting a session from
> scratch. Dated `HANDOFF-*.md` files are frozen snapshots of past states.
> To hand the session to a fresh agent, paste `HANDOFF-PROMPT.md`.
> **Last updated: 2026-11-03.**

## 0. TL;DR for a fresh session

- **Standing:** gufo campaign **final: 90/113 (79.6%)** — results of record in
  `reports/final-report-2026-10-26.md`, tagged `final-2026-10-26-90-113-v2`.
  No jobs running; git clean and pushed.
- **In flight:** the **maya campaign** (GLM-5 S/M/L ±MTP on the 23 residual tasks)
  — `reports/maya-campaign-2026-10-31.md`; partial: wasmi solved by all three sizes.
- **Pending (§6):** leaderboard-grade one-shot gufo run, `failed23` batches for the
  maya arms, L/awilix rerun (after the timeout fixes), operator's thinking-budget cut.
- **First actions:** run the §8 preflight, read §5 pending, then continue.

## 1. What this is

- **Corpus:** `deep-swe/` — 113 Harbor-format tasks (datacurve-ai/deep-swe),
  local clone at upstream HEAD `0b9fabb` (same revision the leaderboard uses).
- **Runner:** `pier` (uv tool `datacurve-pier`) driving **mini-swe-agent 2.4.6**
  inside per-trial Docker containers (installed in-container as
  `uv tool install mini-swe-agent --with "litellm==1.105.1"` — the pin, §3.3).
- **Model path:** mini-swe-agent → litellm client → (squid egress proxy in the
  trial container, ports 80/443 only) → `172.17.0.1:80` (host relay container)
  → `127.0.0.1:4000` (LiteLLM proxy) → `strix-halo-1.local:8080` (llama-swap →
  TP2 llama-server on the two Strix Halo boxes).
- **Metric:** `reward` = 1 iff all f2p tests pass AND no p2p test regresses.
  `f2p`/`p2p`/`partial` explain misses. Binary — see the scoring note in the
  final report (17/23 residuals have partial ≥ 0.95).

## 2. Environment map (host: `system76`, Ubuntu)

| Thing | Value |
|---|---|
| Working dir | `/home/ugo/projects/deepswe-test` — **scripts in `scripts/`, logs in `log/`** (reorg 2026-10-26) |
| LiteLLM proxy | systemd **`litellm.service`** (litellm **1.91.0**, 4 workers) → `http://127.0.0.1:4000/v1`; config `~/software/litellm/litellm_config.yaml` — **OPERATOR-MANAGED: never start/stop/restart on your own; file edits + restarts only on explicit operator request** (last such request: 2026-11-03) |
| Router settings | `timeout: 1800` (raised from 600 on 2026-11-03 — long-thinking non-streaming path), `num_retries: 1`, `cooldown_time: 120`, no tpm, `rpm: 1000`; backup `litellm_config.yaml.bak-20261103-0941` |
| Model backend | `strix-halo-1.local:8080` (llama-swap → llama-server) — **gufo = Qwen3.8-Flash-Next Q8, TP2 across two Strix Halo, 2× Thunderbolt 4 (37 Gb/s, 6 µs), 240 GB**; ~45–65 tok/s, context-independent, **contexts > 300 k** (largest accepted: 328,485 tokens; original 262,144 wall removed 2026-10-25) |
| Also served | `maya-glm5-{s,m,l}-tp2[-mtp]` (GLM-5.3 quants: S=2-bit, M slightly higher, L higher), `maya-deepseek-xs`, `halogen-*`, `gufo-*-q4` — `curl :4000/v1/models` for the live list (15 models) |
| Local llama-swap | `system76.local:8080` — only for local test models; **not** part of any benchmark track |
| Port-80 relay | container `deepswe-relay` (`--restart unless-stopped`): host `:80 → 127.0.0.1:4000` (trial egress allows only 80/443) |
| Trial base URL | **`OPENAI_BASE_URL=http://172.17.0.1/v1`** — never `127.0.0.1` (that's the container itself) |
| Host-name pin | `/etc/hosts` pins `127.0.0.1 system76.local`, `nsswitch files first` (mDNS flaked); backup `/etc/hosts.bak-deepswe` |
| squid read timeout | **patched to 3600 s** in pier's egress template (`agent_setup.py` heredoc) — must stay **above** litellm's `timeout`; restore with `scripts/reapply-squid-timeout.sh` |

## 3. Hard-won rules (each cost real downtime)

1. **Docker address pools exhaust:** killing pier with `pkill` skips `compose down`
   and leaks trial networks. All launch scripts reclaim 0-container trial networks
   + probe-create before resuming — or do it by hand first.
2. **Disk:** ~1.5–1.7 GB/task (images + build cache). Reclaim after jobs:
   `./scripts/free-space.sh` (removes per-trial images, caps builder cache 30 GB).
   113-task batch ≈ 170–190 GB peak; check `df -h /` ≥ 40 GB before launches.
3. **Truncated `result.json`** (disk-full eras) crashes `pier job resume` —
   `rerun-failed-trials.sh` quarantines empty/corrupt ones to `<job>/.infra-failed-backup/`.
4. **infra vs model classification:** `RuntimeError` always infra; `NonZero/AgentTimeout`
   only if reward==0 AND the agent log shows the cause (context wall, squid
   `ERR_READ_TIMEOUT`, `litellm.Timeout`, `RepeatedFormatError`…); `reward==1` never touched.
5. **Collector captures committed work only** (`git diff base HEAD`) → an
   uncommitted/aborted session = 0-byte patch = base graded = zero. Hence
   **`commit-incremental.yaml`** (commit-after-each-feature) — pass `--incremental`
   to `rerun-subset.sh` / use `-c` with `run_deepswe.sh`. It cannot help when
   `RepeatedFormatError` aborts before any commit (3 near-misses lost this way).
6. **Safe kill:** `pkill -f "^/home/ugo/.local/share/uv/tools/datacurve-pier/bin/python .*pier"`
   (never a broad pattern — it self-killed twice). SIGTERM is ignored → use `-9`.
   After any kill: reclaim networks (rule 1).
7. **pier upgrades wipe site-packages edits.** After `uv tool upgrade datacurve-pier`
   run **both**: `./scripts/reapply-litellm-pin.sh` and `./scripts/reapply-squid-timeout.sh`.
8. **No model probes unless the operator asks** (they show on dashboards); preflight
   warm-ups inside launch scripts are fine. Verify launches via logs/scoreboard.

## 4. Where things stand (results)

**gufo campaign — final, 90/113 (79.6%)**: main 66 → +1 arktype 67 → +3 zeros 70
→ +8 failed13 78 → +10 nearmiss 88 → +2 wallvictims 90. Full analysis:
`reports/final-report-2026-10-26.md` (§2 = three platform-fix phases, §3 = failure
taxonomy of the 23 residuals, §4 = attribution, §6 = leaderboard comparison).

**Residual 23** (the `failed23` group): 3 chronic p2p regressors (gql/bandit/pest —
deterministic, same test every attempt), ~17 one/few-f2p-test misses (half with
identical failing tests across attempts), 3 harness-wiped near-misses (meriyah
45/49→0/49, koota-pair 37/38→0/38, updo 15/17→0/17), kombu (deliberate empty diff).
Zero-pass (reward=0, f2p 0/N) in gufo's final view: **updo, wasmi, koota-pair, meriyah**.

**maya campaign — in progress** (`reports/maya-campaign-2026-10-31.md`):
- `wasmi-trap-coredumps` **solved 22/22 by maya-{s,m,l}-tp2-mtp** (first attempt each);
  S burned 2× output / 3× input tokens of M for the same score (quant-efficiency signal)
- `awilix`: maya-m **23/24 — the identical single test gufo fails** (task-edge, not
  model); maya-l **2× infra death** (long-think vs non-streaming → now fixed by the
  timeout patches) → **rerun pending**
- S is a 2-bit GLM-5.3 quant, M slightly higher, L higher — the gufo-vs-GLM
  comparison is the operator's quant-quality question (scorecard idea in the report)

**Platform incidents** (all found by the benchmark, all fixed): litellm router
misconfig (tpm/timeout/retries, fixed 10-18), output-token cap (truncations in
~30% of rerun-batch trials), 262k context wall (fixed 10-25), squid 15-min default
read timeout vs long thinking (fixed 11-03), plus a historic squid timeout on
`kcp-go` and one operator restart — see final report §2 for evidence per phase.

## 5. Operators/agreements (standing)

- Operator runs long jobs themselves with `nohup`; agent verifies via logs/scoreboard.
- **`litellm.service`, model backends, pier site-packages edits: operator's domain** —
  edits on explicit request; restarts only when explicitly told (2026-11-03 was explicit).
- Reports live in `reports/` and get committed with results changes; commit messages
  document each incident/config change — keep that practice.
- Scoreboard of record + tags: `final-2026-10-26-90-113` (first), `…-v2` (report v2).

## 6. Pending work (in order)

1. **Leaderboard-grade one-shot** (Pass@1, stock config, no reruns) — the number
   comparable to their 74% top (our metric-identical pass@1 was 66/112 = 58.9%, but
   measured on the then-broken platform):
   ```bash
   nohup ./scripts/run_deepswe.sh gufo-qwen3.8-flash-next-tp2-q8 \
     -n 2 -j deepswe-gufo-qwen3.8-flash-next-tp2-q8-leaderboard \
     > log/leaderboard-start.log 2>&1 &
   ```
   ~4–4.5 days at `-n 2`, 170–190 GB disk. Rules: no config changes mid-run, no
   reruns of failures (any retry = best-of-k).
2. **maya `failed23` batches** (one column per model; guard drops that model's solves):
   ```bash
   MODEL=maya-glm5-m-tp2-mtp  ./scripts/rerun-subset.sh failed23 --incremental -n 2
   ```
   arms: `maya-glm5-{s,m,l}-tp2`, `maya-glm5-{s,m,l}-tp2-mtp`, optionally
   `gufo-qwen3.8-flash-next-tp2-q4` (same-weights quant A/B) and gufo post-upgrade retest.
   ~17–18 h/arm at `-n 2`, ~40 GB; `free-space.sh` between arms.
3. **maya-l awilix rerun** (both prior attempts were infra deaths; timeout fixes in place).
4. **Operator:** reduce thinking budget server-side (their step, after the timeout work).
5. Optional: streaming end-to-end (mini-swe 2.4.6 has **no** LLM streaming — verified
   from the wheel; `model_kwargs: {stream: true}` would break `LitellmResponseModel`,
   which expects a completed response. A ~15-line patch folding the
   `response.completed` event + pier install-hook is the path; `stream_timeout` in
   litellm config is already supported when that lands).

## 7. File inventory

| File | Purpose |
|---|---|
| `scripts/run_deepswe.sh` | main launcher: `-l/-t/-n/-s/-j/-c/-d/-w`; `-c FILE` injects any agent YAML (e.g. `commit-incremental.yaml`), `-j` sets job name (refuses existing), `--dry` prints the pier command without launching |
| `scripts/rerun-subset.sh` | engine for subset batches: groups `zeros\|nearmiss\|failed13\|wallvictims\|failed23`; `--incremental`, `--tag`, `-n`, `--dry`, `MODEL=<id>` override |
| `scripts/rerun-{zeros,nearmiss,failed13,wallvictims}.sh` | thin wrappers (failed13/wallvictims force `--incremental`) |
| `scripts/rerun-failed-trials.sh` / `start-rerun.sh` | resume-with-repair (quarantine, network reclaim, concurrency edit) |
| `scripts/scoreboard.sh` | live results (`./scripts/scoreboard.sh [job-dir] [-n s]`) |
| `scripts/reapply-litellm-pin.sh` / `reapply-squid-timeout.sh` | restore pier site-packages patches after upgrades |
| `scripts/free-space.sh` | reclaim per-trial images + cap builder cache |
| `commit-incremental.yaml` | agent config with commit-mandate (use via `--incremental`/`-c`) |
| `reports/final-report-2026-10-26.md` | **gufo results of record** (+ addendum: wasmi solved by maya) |
| `reports/maya-campaign-2026-10-31.md` | maya campaign matrix + datapoints |
| `reports/*` | earlier analysis (zeros-rerun, nearmiss-rerun, zero-pass, per-task) |
| `log/` | all run logs (gitignored); `jobs/` | per-trial results (gitignored) |
| `README.md` | full setup docs (§3 host, §3.5 pier patches, §4 runs, §6 troubleshooting) |

## 8. Fresh-session preflight

```bash
cd /home/ugo/projects/deepswe-test
git status -s && git status -sb          # clean; in sync with origin
systemctl is-active litellm              # active (operator's — do not touch)
docker ps --format '{{.Names}}' | grep deepswe-relay    # present
grep -c 'litellm==1.105.1' /home/ugo/.local/share/uv/tools/datacurve-pier/lib/python*/site-packages/pier/agents/installed/mini_swe_agent.py   # 1 = pin intact
grep -c '^read_timeout 3600 seconds' /home/ugo/.local/share/uv/tools/datacurve-pier/lib/python*/site-packages/pier/environments/agent_setup.py  # 1 = squid patch intact
grep -n 'timeout: 1800' ~/software/litellm/litellm_config.yaml                   # present
pgrep -af "bin/python .*pier" | grep -v grep        # empty = no job running
curl -s -m 15 -o /dev/null -w '%{http_code}\n' http://127.0.0.1:4000/v1/models  # 200
df -h / | tail -1                                  # ≥ 40 GB (113-task runs want ~200 GB)
ls HANDOFF.md                                      # you are here
```

## 9. Cheat sheet

```bash
# full run / single task (stock or -c config)
./scripts/run_deepswe.sh --list
./scripts/run_deepswe.sh <model> -n 2 -j <job-name> [-c commit-incremental.yaml] [--dry]

# subset batches
MODEL=<id> ./scripts/rerun-subset.sh failed23 --incremental -n 2   # 23-task residual set
./scripts/rerun-subset.sh wallvictims --incremental [--tag r2]

# watch
./scripts/scoreboard.sh [jobs/<job>]
tail -f log/<job>.log
grep -m1 -c "Commit Incremental Work" jobs/<job>/*/agent/mini-swe-agent.txt   # 1 = config active
grep Traceback log/<job>.log    # must print nothing
```
