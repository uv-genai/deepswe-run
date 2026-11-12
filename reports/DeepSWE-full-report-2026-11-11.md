# DeepSWE — Full Report: results, performance, model quality, task catalog

**Date:** 2026-11-11 · **Model track:** gufo (`gufo-qwen3.8-flash-next-tp2-q8`) + maya arms
(GLM-5.3 S/M/L ±MTP, DeepSeek v4.1 Flash Q1/Q2/3 ±MTP) · **Runner:** Pier + mini-swe-agent 2.4.6
(litellm pinned 1.105.1), commit-mandate agent config, serial · **Scoring:** binary `reward`
(all f2p pass AND no p2p regression); `partial` = mean test pass rate.

> **This is the single consolidated report.** It merges: `final-report-2026-10-26.md`
> (gufo campaign), `failed23-arm-comparison-2026-11-10.md` (three-arm results +
> performance), `model-comparison-2026-11-04.md` (profiles, quant-vs-size, effort),
> `failed23-task-guide-2026-11-09.md` (task descriptions + complexity), and
> `maya-campaign-2026-10-31.md` (datapoints). Those files remain as detail archives;
> **numbers here supersede them where they differ** (corrections noted inline).

---

## 1. Current standing

| Scope | Result |
|---|---|
| **gufo on the full 113-task corpus** | **94/113 (83.2 %)** — 66 (main) → 67 → 70 → 78 → 88 → 90 → 91 (wasmi, attempt 7) → **94** (its own failed23 arm: fastapi-deprecation, fastapi-implicit, pebble) |
| **The 23-task residual set, best across all models** | **17/23 solved by ≥1 model; 6 open for everyone:** `bandit`, `gql`, `ink-grid`, `meriyah`, `pest`, `termenv` |
| Per family on the 23-set | **deepseek 13/23** · **glm5-m 11/23** · gufo 4/23 |
| Zero-pass trials (reward 0, f2p 0/N) | **none remaining** (was the historical signature of harness casualties — now cleared) |
| Open platform item | ⚠️ the **`maya-deepseek-s-mtp` backend still enforces a 262k context** (its batch wasmi died at prompt 262,222) — gufo/glm backends are raised past 300k |

---

## 2. Protocol & platform (what makes the numbers comparable)

- **Platform:** gufo — two Strix Halo machines, TP2, 2× Thunderbolt 4 (37 Gb/s, 6 µs),
  240 GB; Qwen3.8-Flash-Next Q8 at ~45 tok/s sustained (peaks >65), context-independent,
  contexts >300 k (largest accepted prompt: 328,485 tokens). 3.31 B input tokens /
  21.7 M output tokens served across the campaign (99 % prefix-cache hits).
- **Path:** mini-swe → LiteLLM proxy (pinned 1.105.1, router `timeout 1800`) → port-80
  relay → backend. All trial traffic non-streaming; squid `read_timeout 3600`.
- **Config:** every failed23 arm ran the **commit-mandate config** (`commit-incremental.yaml`
  via `--incremental`), serial (`n=1`…`2`), post-timeout-hardening → arms are directly comparable.
- **Agent config evolution matters for the gufo baseline:** the main run (66/113) executed
  on a partially misconfigured stack (LiteLLM router, low output-token cap, concurrency);
  three platform-fix phases are documented in `final-report` §2 — later batches all ran fixed.

---

## 3. Gufo campaign of record (113 tasks)

| Stage | Window | Graded | New solves | Cumulative |
|---|---|---|---|---|
| Main run (stock config) | 10-16 → 10-21 | 112 | 66 | 66 |
| arktype standalone | — | 1 | +1 | 67 |
| zeros rerun | 10-21 → 10-22 | 16 | +3 | 70 |
| failed13 rerun (`--incremental`) | 10-22 → 10-23 | 13 | +8 | 78 |
| nearmiss rerun (`--incremental`) | 10-23 → 10-24 | 34 | +10 | 88 |
| wall victims (context raised) | 10-25 | 6 | +2 | 90 |
| wasmi attempt 7 (post-upgrade) | 11-07 | 1 | +1 | 91 |
| **failed23 arm** | 11-08 | 22 | **+3** | **94** |

**What moved the score:** commit-mandate config (+8/13 on failed13 — 7 of those had lost
all work uncommitted), the context raise (+2 wall victims), plain pass@2 re-runs (+3),
and the platform fixes as precondition for everything after the main run. Detailed
failure taxonomy: `final-report` §3 (p2p regressors, single-edge misses, harness
casualties, rabbit-holes) — condensed in §7 below.

**Leaderboard note:** the public board (`deepswe.datacurve.ai`) reports Pass@1, top = 74 %.
Our metric-identical one-shot was 66/112 (58.9 %) *on the broken platform*; 94/113 is
best-of-k across fixes. The leaderboard-grade one-shot on the fixed platform is still pending.

---

## 4. The failed23 campaign — three arms + solos (the 23-task set)

**Arms** (all commit-mandate, serial):

| Arm | Model | Window | Graded | Solved in arm |
|---|---|---|---|---|
| A | `gufo-qwen3.8-flash-next-tp2-q8` | Nov 8 | 22/22 (wasmi pre-solved → guard-dropped) | 3 |
| B | `maya-glm5-m-tp2-mtp` | Nov 8–9 | 22/22 (wasmi pre-solved → guard-dropped) | 9 |
| C | `maya-deepseek-s-mtp` | Nov 9–10 | 23/23 (awilix ran: guard didn't match the earlier solve's `-dspark` id) | 10 |
| solos | deepseek-s-dspark: wasmi, updo · glm5-m: effect-sse | 11-10/11 | 3/3 | 3 |

### Results matrix (23 tasks; ✅ = reward 1)

| Task | gufo Q8 | glm5-m | ds-s-mtp | notes |
|---|---|---|---|---|
| fastapi-implicit-head | ✅43/43 | ✅43/43 | ✅43/43 | all three |
| fastapi-deprecation | ✅137/137 | ✅137/137 | 136/137 | |
| pebble-durability | ✅59/59 | ✅59/59 | 57/59 | |
| kombu-virtual-queue | 68/76 | ✅76/76 | ✅76/76 | gufo once submitted a *deliberate* empty diff |
| mashumaro-flatten | 63/66 | ✅66/66 | ✅66/66 | |
| prometheus-reload | 10/15 | ✅15/15 | ✅15/15 | glm solved via commit-mandate after a loop-timeout trial |
| kea-signal-selectors | 11/12 | ✅12/12 | 10/12 | identical failing test in every gufo attempt |
| koota-pair-tracking | 37/38 | ✅38/38 | 37/38 | once harness-wiped to 0/38 |
| updo-policy-alerting | 16/17 | ✅17/17 | 11/17 → **✅ solo 17/17** (11-10) | |
| awilix-async-init | 23/24 | 23/24 | ✅24/24 (in-arm; also ✅ solo 11-04) | the single edge test; only deepseek passes it |
| csstree-shorthand | 75/79 | 74/79 | ✅79/79 | |
| effect-sse-streaming | 46/47 | **0/47** → **✅ solo 47/47** (11-11) | ✅47/47 | |
| httpx-multipart | 98/122 | 121/122 | ✅122/122 | |
| koota-deferred-buffer | 69/71 | 67/71 | ✅71/71 | biggest reference solution (1031 ln) |
| obsidian-link-format | 59/60 | 59/60 | ✅60/60 | |
| bandit-nosec | 69/69 ⚠️p2p | 68/69 | 67/69 | **open** — chronic p2p regressor |
| gql-incremental | 17/17 ⚠️p2p | 17/17 ⚠️p2p | 16/17 | **open** — chronic p2p regressor |
| httpx-streaming-json | 107/108 | 106/108 | 107/108 (batch) → **✅ 108/108 solo** (11-11) | the ndjson edge — deepseek is the only solver |
| ink-grid-layout | 21/25 | 23/25 | 23/25 | **open** — was a context-wall victim |
| meriyah-using | 48/49 | 48/49 | 48/49 | **open** — *identical* 48/49 from all three |
| pest-charclass | 100/104 ⚠️p2p | 103/104 | 104/104 | **open** — p2p regressor / whack-a-mole |
| termenv-ansi | 30/35 | 34/35 | 34/35 | **open** — width-0 OSC edge |
| wasmi-coredumps | ✅22/22 (attempt 7, pre-arm) | ✅22/22 (pre-arm solo) | batch **0/22** → **✅ solo 22/22** (11-10) | batch death = **262k context wall** (prompt 262,222) on the s-mtp deployment — *corrects the earlier "empty patch, requeue pending" note* |

**Union: 17/23 solved · 6 open for every arm.**

---

## 5. Performance & efficiency (turns, time, tokens)

### 5.1 Three-arm totals — the 22 tasks common to all arms (wasmi excluded)

| Metric | gufo Q8 | glm5-m | ds-s-mtp |
|---|---|---|---|
| Total agent time | **20.1 h** 🥇 | 26.6 h † | 21.4 h |
| Mean time / task | **55 min** 🥇 | 73 min † | 59 min |
| Slowest single task | 92 min | **180 min** † | 105 min |
| **Total turns (steps)** | 2,874 | 3,080 | **2,347** 🥇 |
| **Mean turns / task** | 131 | 140 | **107** 🥇 |
| sec/step | **25.2** 🥇 | 31.1 | 32.9 |
| Total input tokens | 399 M | 310 M | **234 M** 🥇 |
| Input / step | 139 k | 101 k | 100 k |
| Total output tokens | 2,654 k | **1,759 k** 🥇 | 1,784 k |
| Output / step | 923 | **571** | 760 |
| Cache hit | 98.3 % | 98.8 % | **99.0 %** |
| Effective out tok/s ‡ | **36.6** 🥇 | 18.4 | 23.1 |

† glm's mean is skewed by its `prometheus` trial: 180 min / 429 steps of `sleep 28`
polling with ~0 tokens — it still scored 15/15 (commit-mandate captured the earlier
work). Excluding it: ~67 min/task, 2,651 steps.
‡ output tokens ÷ wall time (includes thinking + tool idle) — *not* raw decode speed
(the platform decodes ~45 tok/s for all three); it measures productive generation share.

### 5.2 Cost per solved task — the number that matters

| | gufo Q8 | glm5-m | ds-s-mtp |
|---|---|---|---|
| Solved (of 22) | 3 | 9 | **10** |
| **Output tokens per solve** | 885 k | 195 k | **178 k** 🥇 |
| **Agent-hours per solve** | 6.7 h | 3.0 h | **2.1 h** 🥇 |
| Input tokens per solve | 133 M | 34 M | 23 M |

**deepseek converts ~5× fewer output tokens and ~3× less wall time per solve than gufo.**

### 5.3 Arm quality (graded trials)

| | gufo | glm5-m | ds-s-mtp |
|---|---|---|---|
| Mean partial | **0.9896** 🥇 | 0.9784 | 0.9823 |
| Mean f2p | 94.7 % | 94.7 % | **96.8 %** 🥇 |

gufo never has zeros — its failures are narrow misses; deepseek converts the most
near-misses into full solves.

### 5.4 Solo re-runs (effort)

| Run | Result | Time | Turns | Output | Patch |
|---|---|---|---|---|---|
| deepseek-s · wasmi | ✅22/22 | 99 min | 150 | 85.4 k | 62 KB |
| deepseek-s · updo | ✅17/17 | 56 min | 73 | 87.0 k | 71 KB |
| deepseek-s · httpx-streaming | ✅108/108 | 64 min | 84 | 93.3 k | 21 KB |
| glm5-m · effect-sse | ✅47/47 | 180 min | 221 | 73.0 k | 48 KB |

**deepseek-s 6-task tiebreaker run (11-12, all reward 0):** bandit 51 min/90 turns
(f2p 69/69, p2p broken) · gql 57 min/122 (f2p 17/17, p2p broken) · ink 76 min/132
(21/25) · meriyah 76 min/162 (45/49) · pest 54 min/129 (f2p 103/104 + p2p broken) ·
termenv 51 min/62 (30/35) — signatures in §6.3.

### 5.5 Deep-dive effort tables (same task, many models)

**wasmi — five runs, one identical score** (+ deepseek solo):

| | gufo Q8 | gufo Q4 | glm-S (2-bit) | glm-M | glm-L | **ds-s** |
|---|---|---|---|---|---|---|
| Result | ✅22/22 | ✅22/22 | ✅22/22 | ✅22/22 | ✅22/22 | ✅22/22 |
| Time | **67 min** | 69 | 163 | 81 | 100 | 99 |
| Turns | **182** | 250 | 308 | 195 | 227 | **150** |
| sec/step | 22 | **17** | 32 | 25 | 26 | — |
| Input | 39.3 M | 53.0 M | 73.5 M | **24.7 M** | 28.7 M | — |
| Output | 164.4 k | 203.6 k | 185.9 k | **92.8 k** | 94.4 k | 85.4 k |

**awilix — the edge task (9 attempts, 1 solver, then a second):**

| Attempt | Result | Time | Turns | Output |
|---|---|---|---|---|
| deepseek-s Q2/3 solo (11-04) | ✅24/24 | 54 min | 74 | 83.6 k |
| deepseek-xs Q1 | 23/24 (same test) | 51 min | 55 | 62.4 k |
| glm5-m | 23/24 (same test) | 46 min | 80 | 62.5 k |
| glm5-l (post-fix) | 23/24 (same test) | 61 min | 74 | 77.7 k |
| gufo Q8 (×2, +batch) | 23/24 (same test) | 39–103 min | 73–123 | ~97–101 k |
| gufo Q4 | 23/24 (same test) | 45 min | 114 | 123.4 k |

---

## 6. Model quality analysis

### 6.1 Profiles

- **DeepSeek v4.1 Flash (Q2/3) — the edge-closer and the efficiency winner.** Seven unique
  solves no other arm reached (awilix, csstree, effect-sse, httpx-multipart,
  koota-deferred, obsidian-link, httpx-streaming): it converts the 95–99 % stall-outs into
  full solves.
  Best cost-per-solve on every axis (178 k output, 2.1 h), fewest turns, best cache.
  Its Q1 sibling still scored 23/24 on awilix → bit-robustness. Weakness: its *batch*
  run left two near-misses unconverted (updo 11/17, kea 10/12) — the solos fixed updo.
- **GLM-5.3 M — the thorough middle.** Broadest mid-difficulty win set (9 in-arm),
  including the task that took gufo seven attempts (wasmi). Most turns, longest wall
  (one pathological polling trial aside), lowest productive-generation share — it buys
  completeness with time.
- **gufo Qwen3.8 Q8 — fastest, narrowest, never catastrophic.** Wins every raw-speed
  metric (25 s/step, 36.6 eff tok/s) but the **least efficient per outcome** (6.7 h and
  885 k output per solve). Highest *mean partial* (0.9896): its misses are single tests,
  never zeros. On the full corpus it is still the only board-grade evidence (94/113).
  Known behavioral weaknesses: chronic p2p regressors (breaks existing tests), rabbit-holing
  on huge specs (historically), submission fragility (fixed by commit-mandate).

### 6.2 Quantization vs model size (controlled where possible)

1. **Bits buy cost, not capability — until Q1.** Same-weights **Q8 vs Q4** produced
   *identical outcomes* on both test tasks (wasmi solved by both, awilix missed by the
   same test): Q4 paid +37 % turns / +24 % output but decoded 23 % faster → wall time
   within 3 %. GLM S(2-bit) matched M's outcomes at ~2× tokens. DeepSeek **Q1** lost
   exactly one test vs Q2/3 → the correctness tax only appears at the extreme low end.
2. **Model size bought nothing measurable:** GLM L ≡ GLM M in results, near-identical
   cost (+1.7 % output); L's only difference is longer thinking (latency — absorbed by
   the raised timeouts after the 792 s incident).
3. **Family/behavior dominates bit depth:** the highest-bit model in the comparison
   (Qwen **Q8**) lost *both* deep-dive tasks to lower-bit rivals. gufo's failures are
   behavioral (regression-proneness, edge engagement), not precision — which is also
   why more bits never helped it.

### 6.3 The deterministic core (why 7 tasks stay open)

- **Chronic p2p regressors — now proven cross-family (gufo *and* deepseek):** `gql`
  breaks the *byte-identical* existing test
  (`test_execute_incremental_on_unsupported_transport_raises`) in every attempt by both
  families; `bandit` breaks `test_058_region_unioned_across_statement_lines` in both;
  `pest` toggles (perfect f2p + broken p2p, or the inverse — never both). On bandit and
  gql **f2p is 100 %** — the failure is collateral damage to an existing test, so these
  three p2p suites are sensitive to *any* reasonable implementation, not to a model gap.
- **Broad multi-corner tasks (not single-edge):** deepseek's 11-12 tiebreaker run went
  **0/6** — `ink-grid` 21/25, `meriyah` 45/49 (different corners than the arms' shared
  48/49), `termenv` 30/35, each with *different* failing tests than earlier attempts.
  The remaining non-regressor tasks are hard in a scattered way, not pinned to one line
  (`httpx-streaming`'s single ndjson edge, by contrast, fell to deepseek solo on 11-11).
- **Verdict on "best model":** on the 23-set deepseek leads **13 vs 11** (gufo 4) — but
  it's a small margin over non-identical protocols (batch vs solos; one id-mismatch
  extra attempt). The **7-task tiebreaker** (both families rerun `failed23`, guard now
  selects exactly those 7) would settle it; only a full 113-task pass@1 run can crown an
  overall winner (only gufo has one).

---

## 7. Failure taxonomy (what actually zeros trials)

| Class | Signature | Status |
|---|---|---|
| **Context wall** | `prompt exceeds N-token context`, 400 `context_length_exceeded`, retried ~12×, empty patch | Fixed on gufo/glm backends (>300 k). ⚠️ **still active on `maya-deepseek-s-mtp` (262k)** — killed its batch wasmi at 262,222 |
| **Submission/harness** | work done, 0-byte patch, `RepeatedFormatError` or submit quirk → base graded | Mitigated by commit-mandate; 3 historical near-misses wiped before it; still fires when the abort precedes any commit |
| **Output-token cap** | `finish_reason=length` truncations mid-tool-call | Fixed (cap raised); was ~30 % of rerun-batch trials before |
| **Long-think vs non-streaming** | litellm 600 s read timeout / squid 900 s default; `ERR_READ_TIMEOUT` | Fixed (litellm 1800, squid 3600) — root cause was one 792 s request |
| **Infra flakes** | squid timeouts (`kcp-go`), GitHub release-CDN **504 on the uv download** (killed 5/22 builds in one arm) | Fixed: pier patch = 5× retry + PyPI fallback; reapply script |
| **Rabbit-hole** | model never engages with the spec (wasmi attempt 5: 209 read-only steps, unrelated fix) | Model-side; recovered on later attempts |
| **Chronic p2p regressor** | reward 0 with f2p 100 % — breaks an existing test | Open (gql/bandit/pest) — §6.3 |

---

## 8. The 23-task catalog (what each task is + complexity)

Rubric = three intrinsic factors (reference-solution lines, spec length, f2p breadth),
0–9 → simple/medium/hard. Every reference solution is 470–1031 lines — **no toy tasks**;
"simple" means a several-hundred-line feature. Distribution: 6 simple · 15 medium · 2 hard.

| Tier | Task | Lang / Repo | What it asks for | Spec | Ref-sol | f2p | Status |
|---|---|---|---|---|---|---|---|
| hard | `fastapi-deprecation-response-headers` | py / fastapi | Deprecation/Sunset/`Link` headers + OpenAPI metadata + tracking middleware | 3.1 k | 784 ln | 137 | ✅ all three |
| hard | `kombu-virtual-queue-dead-lettering` | py / kombu | Dead-letter routing, TTL expiry, max-length overflow for virtual transport | 4.5 k | 627 ln | 76 | ✅ glm + ds (gufo: deliberate empty diff) |
| medium | `bandit-structured-nosec-directives` | py / bandit | Region + next-line `nosec` directives with selectors, ignore-nosec | 2.8 k | 629 ln | 69 | ❌ open — p2p regressor |
| medium | `csstree-shorthand-expansion-compression` | js / csstree | Lexer methods expanding CSS shorthands ↔ longhands | 2.9 k | 518 ln | 79 | ✅ ds |
| medium | `fastapi-implicit-head-options` | py / fastapi | Implicit HEAD + automatic OPTIONS across routers/includes | 1.7 k | 939 ln | 43 | ✅ all three |
| medium | `httpx-multipart-response-parsing` | py / httpx | Response iterators parsing multipart bodies into parts | 2.2 k | 600 ln | 122 | ✅ ds |
| medium | `httpx-streaming-json-iteration` | py / httpx | Response iterators incrementally parsing streaming JSON | 2.6 k | 523 ln | 108 | ✅ ds (solo, 11-11) — the ndjson edge all arms missed |
| medium | `koota-deferred-mutation-buffer` | ts / koota | Deferred buffer batching entity mutations during query iteration | 1.0 k | 1031 ln | 71 | ✅ ds |
| medium | `pebble-durability-wait-apis` | go / pebble | Durability callbacks, wait methods, notifications, metrics for sync writes | 2.8 k | 654 ln | 59 | ✅ gufo + glm |
| medium | `updo-policy-alerting` | go / updo | Policy alerting: failures, latency, recovery, SSL expiry | 4.6 k | 669 ln | 17 | ✅ glm + ds (solo) |
| medium | `effect-sse-httpapi-streaming` | ts / effect | Typed SSE endpoints, codecs, client handling for HttpApi | 2.3 k | 829 ln | 47 | ✅ ds (batch) + glm (solo) |
| medium | `kea-atomic-signal-selectors` | ts / kea | Atomic selector tracking, dependency health, circular detection | 3.5 k | 669 ln | 12 | ✅ glm |
| medium | `obsidian-linter-link-format-conversion` | ts / obsidian-linter | Wiki ↔ markdown link/image conversion preserving ignored regions | 2.2 k | 769 ln | 60 | ✅ ds |
| medium | `prometheus-transactional-reload-status` | ts / prometheus | Transactional config reload: durable outcomes, rollback, HTTP status | 1.9 k | 973 ln | 15 | ✅ glm + ds |
| medium | `mashumaro-flattened-dataclass-fields` | py / mashumaro | `field_options` flattening nested dataclasses, prefix/rename validation | 0.6 k | 523 ln | 66 | ✅ glm + ds |
| medium | `termenv-preserve-ansi-resets` | go / termenv | ANSI tokenization, reset-preserving truncation, style-aware output | 1.7 k | 512 ln | 35 | ❌ open — width-0 OSC edge |
| medium | `wasmi-trap-coredumps` | rust / wasmi | Opt-in Wasm coredumps: strict binary format, LEB128, 4 custom sections, re-entrant frames | 3.2 k | 596 ln | 22 | ✅ gufo(q8/q4) + glm×3 + ds (solo) — hardest-won (10 attempts) |
| simple | `awilix-async-container-initialization` | ts / awilix | Dependency-aware async init: ordered startup, concurrency limits, rollback | 2.3 k | 557 ln | 24 | ✅ ds only — one edge test blocked 8 other attempts |
| simple | `gql-incremental-graphql-delivery` | py / gql | `@defer`/`@stream` incremental delivery: HTTP multipart, WebSocket, DSL | 1.6 k | 537 ln | 17 | ❌ open — p2p regressor (f2p perfect 4/4) |
| simple | `koota-pair-relation-tracking` | ts / koota | Tracking modifiers distinguishing specific relation pairs | 1.1 k | 547 ln | 38 | ✅ glm |
| simple | `meriyah-explicit-resource-declarations` | ts / meriyah | Parser + AST for `using`/`await using` with context-sensitive errors | 1.4 k | 573 ln | 49 | ❌ open — all three at identical 48/49 |
| simple | `pest-character-class-coalescing` | rust / pest | Optimizer passes collapsing choice chains into character classes | 1.2 k | 471 ln | 104 | ❌ open — p2p regressor / whack-a-mole |
| simple | `ink-grid-box-layout` | ts / ink | CSS Grid parsing/placement in Box: tracks, gaps, positioning | 0.9 k | 479 ln | 25 | ❌ open — ex-context-wall victim (23–24/25) |

---

## 9. Open items / next steps

1. **The 6-task tiebreaker — first leg run (11-12, deepseek-s): 0/6** (3 p2p-regressor
   failures with perfect/near-perfect f2p + 3 genuine misses below previous bests);
   the6 remain open, deepseek stays 13/23. Second leg when convenient:
   `./scripts/launch-failed-model.sh maya-glm5-m-tp2-mtp` (guard selects exactly the 6).
   A gufo retry of the 3 regressors under a "never modify existing tests" prompt would
   also be informative.
2. **Raise the `maya-deepseek-s-mtp` backend context** (still 262k — it cost a wasmi batch).
3. **Leaderboard-grade one-shot** for gufo (stock config, single attempt, fixed platform) —
   the only number comparable to the board's 74 % top.
4. Remaining arms if wanted: `maya-glm5-{s,l}-tp2[-mtp]`.
5. Chronic p2p regressors: consider an agent-prompt constraint ("never modify existing tests")
   or a harness-level p2p guard.

## 10. Source archives (detail kept, numbers superseded by this report)

`final-report-2026-10-26.md` (gufo campaign of record + leaderboard analysis) ·
`failed23-arm-comparison-2026-11-10.md` (three-arm tables) ·
`model-comparison-2026-11-04.md` (profiles/quant) ·
`failed23-task-guide-2026-11-09.md` (task metadata) ·
`maya-campaign-2026-10-31.md` (matrix + datapoints) ·
`quant-sensitive-tasks.md` (scorecard plan) ·
`zeros-rerun-analysis-2026-10-21.md`, `nearmiss-rerun-results-2026-10-24.md`,
`zero-pass.md`, `near-misses.md`, `summary.md`, `analysis-*.md` (early campaign) ·
per-trial raw data under `jobs/` (186+ trials: `result.json`, `reward.json`, `ctrf.json`).
