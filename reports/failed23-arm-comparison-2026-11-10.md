# failed23 — full three-arm comparison (results + performance)

**Date:** 2026-11-10 · **Task set:** the static `failed23` group (23 tasks unsolved by
gufo at the final-report cut; see `failed23-task-guide-2026-11-09.md` for per-task
descriptions and complexity tiers)
**Arms** (all: commit-mandate config `commit-incremental.yaml`, `--incremental`,
serial, same gufo platform, post-timeout-hardening):

| Arm | Model id | Window | Graded | Solved in arm |
|---|---|---|---|---|
| A | `gufo-qwen3.8-flash-next-tp2-q8` | Nov 8 | 22/22 (wasmi pre-solved → guard-dropped) | 3 |
| B | `maya-glm5-m-tp2-mtp` | Nov 8–9 | 22/22 (wasmi pre-solved → guard-dropped) | 9 |
| C | `maya-deepseek-s-mtp` | Nov 9–10 | 23/23 (awilix not dropped — earlier solve sits under id `-dspark`, guard didn't match) | 10 |

**Per-model count on the full 23-task set** (best across all their attempts, counting
pre-arm solves): **glm5-m = 10/23** (9 + wasmi) · **deepseek-s = 10/23** (10, but it
*failed* wasmi) · **gufo = 4/23** (3 + wasmi) — **dead tie between B and C, opposite
profiles.**

---

## 1. Results

| Task | gufo Q8 | glm5-m | ds-s-mtp |
|---|---|---|---|
| fastapi-implicit-head | ✅43/43 | ✅43/43 | ✅43/43 |
| fastapi-deprecation | ✅137/137 | ✅137/137 | 136/137 |
| pebble-durability | ✅59/59 | ✅59/59 | 57/59 |
| kombu-virtual-queue | 68/76 | ✅76/76 | ✅76/76 |
| mashumaro-flatten | 63/66 | ✅66/66 | ✅66/66 |
| prometheus-reload | 10/15 | ✅15/15 | ✅15/15 |
| kea-signal-selectors | 11/12 | ✅12/12 | 10/12 |
| koota-pair-tracking | 37/38 | ✅38/38 | 37/38 |
| updo-policy-alerting | 16/17 | ✅17/17 | 11/17 |
| awilix-async-init | 23/24 | 23/24 | ✅24/24 |
| csstree-shorthand | 75/79 | 74/79 | ✅79/79 |
| effect-sse-streaming | 46/47 | **0/47** ⚠️ | ✅47/47 |
| httpx-multipart | 98/122 | 121/122 | ✅122/122 |
| koota-deferred-buffer | 69/71 | 67/71 | ✅71/71 |
| obsidian-link-format | 59/60 | 59/60 | ✅60/60 |
| bandit-nosec | 69/69 ⚠️p2p | 68/69 | 67/69 |
| gql-incremental | 17/17 ⚠️p2p | 17/17 ⚠️p2p | 16/17 |
| httpx-streaming-json | 107/108 | 106/108 | 107/108 |
| ink-grid-layout | 21/25 | 23/25 | 23/25 |
| meriyah-using | 48/49 | 48/49 | 48/49 |
| pest-charclass | 100/104 ⚠️p2p | 103/104 | 104/104 |
| termenv-ansi | 30/35 | 34/35 | 34/35 |
| wasmi-coredumps | ✅22/22 (attempt 7) | ✅22/22 (arm guard-dropped; solved earlier) | **0/22** ⚠️ empty patch, `NonZeroAgentExitCodeError` |

**Headline:** union of the three arms = **16/23 solved**; **7 open for every arm**:
`bandit`, `gql`, `httpx-streaming`, `ink-grid`, `meriyah`, `pest`, `termenv`.

**Profiles:**
- **glm5-m (10):** the reliable middle — fastapi×2, pebble, kombu, mashumaro, prometheus,
  kea, koota-pair, updo, wasmi. Wins the mid-difficulty cluster + the task that took
  gufo seven attempts.
- **ds-s-mtp (10):** the edge-finder — **6 unique** solves neither other arm reaches
  (awilix, csstree, effect-sse, httpx-multipart, koota-deferred, obsidian-link), minus
  wasmi which it could not touch (empty patch — needs a requeue before counting as a
  true capability loss).
- **gufo (4):** all its in-arm solves are shared with glm — 0 unique wins here; but it
  has the **highest mean partial (0.9896)** — its failures are narrow misses, never
  zeros.
- The **deterministic core** (`meriyah` 48/49 by all three, bandit/gql/httpx-streaming/
  ink/termenv within a few tests of each other in every arm) confirms the task-edge
  reading from the task guide: these 7 are not model-specific.

**Arm quality (graded trials):** mean partial — gufo 0.9896 · ds 0.9823 · glm 0.9784 ·
mean f2p — **ds 96.8%** · gufo 94.7% · glm 94.7%.

---

## 2. Performance (22 tasks common to all three arms; wasmi excluded)

| Metric | gufo Q8 | glm5-m | ds-s-mtp |
|---|---|---|---|
| Total agent time | **20.1 h** 🥇 | 26.6 h | 21.4 h |
| Mean time / task | **55 min** 🥇 | 73 min † | 59 min |
| Slowest single task | 92 min | **180 min** † | 105 min |
| Total turns (steps) | 2,874 | 3,080 | **2,347** 🥇 |
| Mean turns / task | 131 | 140 | **107** 🥇 |
| sec/step | **25.2** 🥇 | 31.1 | 32.9 |
| Total input tokens | 399 M | 310 M | **234 M** 🥇 |
| Input / step | 139 k | 101 k | 100 k |
| Total output tokens | 2,654 k | **1,759 k** 🥇 | 1,784 k |
| Output / step | 923 | **571** | 760 |
| Cache hit | 98.3% | 98.8% | **99.0%** |
| Effective out tok/s ‡ | **36.6** 🥇 | 18.4 | 23.1 |

† glm's mean is skewed by the `prometheus` trial: 180 min / 429 steps, ~2 h of
`sleep 28` polling loops with zero tokens (it still scored 15/15 — commit-mandate
captured the earlier work). Excluding it: ~67 min/task, 2,651 steps.
‡ output tokens ÷ wall time — includes thinking and tool-execution idle, so it is
**not** raw decode speed: the platform decodes at ~45 tok/s for all three. It measures
how much of the wall clock is productive generation.

### Cost per solved task (the number that matters)

| | gufo Q8 | glm5-m | ds-s-mtp |
|---|---|---|---|
| Solved (of 22) | 3 | 9 | **10** |
| Output tokens per solve | **885 k** | 195 k | **178 k** 🥇 |
| Agent-hours per solve | **6.7 h** | 3.0 h | **2.1 h** 🥇 |
| Input tokens per solve | 133 M | 34 M | 23 M |

**deepseek costs ~5× fewer output tokens and ~3× less time per solve than gufo.**

### Reading

1. **gufo: fastest per step, least efficient per outcome.** It wins every raw-speed
   metric (25 s/step, 36.6 eff tok/s) but re-reads the most context (139 k in/step),
   writes the longest responses (923 out/step), and converts all of it into the fewest
   solves — fast and chatty, not thrifty.
2. **ds-s-mtp is the efficiency winner:** fewest turns, least input, best cache, most
   solves. It does less work per task and still lands the edge cases.
3. **glm5-m is the thorough one:** most turns, longest wall (one pathological loop
   trial aside), lowest effective generation share — and a solid middle-price solve
   count.
4. **Cache ≈ 99% everywhere** — input tokens are nearly free platform-side; the real
   differentiators are turns, output volume, and wall time.
5. Same backend, same agent config, serial runs → the comparison is clean.

---

## 3. Anomalies & follow-ups

- **ds wasmi 0/22**: 0-byte patch + `NonZeroAgentExitCodeError` after 149 steps
  (p2p green) — empty-patch/harness class, **not proven capability**; requeue it before
  drawing conclusions (it is the only one of the 23 ds never legitimately attempted).
- **glm effect-sse 0/47**: its only zero-f2p in the arm — same inspection warranted.
- **Guard id mismatch**: arm C ran as `maya-deepseek-s-mtp` while the earlier awilix
  solve lives under `maya-deepseek-s-dspark` → the solved-guard did not match and the
  task ran twice (it re-solved 24/24, so no harm — but model ids must stay stable for
  the guard to work across arms).
- **Chronic p2p regressors** (`gql`, `bandit`, `pest`) again broke *existing* tests
  rather than failing their own — unchanged from `final-report` §3.1.

## Source data

Per-trial `result.json` (durations, steps, `agent_result` token counts) and
`verifier/reward.json` for the three `jobs/deepswe-*-failed23-rerun-inc` directories.
Companions: `failed23-task-guide-2026-11-09.md` (what the tasks are),
`model-comparison-2026-11-04.md` (wasmi effort table, profiles, quant-vs-size),
`final-report-2026-10-26.md` (gufo campaign of record).
