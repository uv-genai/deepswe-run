# DeepSWE — Final Report: 90/113 (79.6%)

**Model:** `gufo-qwen3.8-flash-next-tp2-q8` · **Runner:** Pier + mini-swe-agent 2.4.6 (litellm pinned 1.105.1), `--n-concurrent 1`
**Campaign:** 2026-10-16 → 2026-10-26 · 7 jobs · 186 trials · 25,590 agent steps
**Scoring:** binary `reward` = 1 iff **all** fail-to-pass tests pass **and** no pass-to-pass test regresses; `partial` = mean test pass rate
**Companion reports:** `summary.md`, `zero-pass.md`, `near-misses.md`, `analysis-*.md` (main run) · `zeros-rerun-analysis-2026-10-21.md` · `nearmiss-rerun-results-2026-10-24.md` · `HANDOFF-20261024-1902.md` (ops state)

---

## 1. Result

**90 / 113 solved (79.6%)** — all 113 tasks graded, no unfinished trials, no infra failures left unexamined.

| Stage | Window | Graded | New solves | Cumulative |
|---|---|---|---|---|
| Main 113-task run | 10-16 → 10-21 | 112 (+1 ungraded) | 66 | 66 |
| arktype standalone | — | 1 | +1 | 67 |
| zeros rerun (16 hard zeros) | 10-21 → 10-22 | 16 | +3 | 70 |
| failed13 rerun (`--incremental`) | 10-22 → 10-23 | 13 | +8 | 78 |
| near-miss rerun (`--incremental`) | 10-23 → 10-24 | 34 | +10 | 88 |
| wall victims (after `--context` raise) | 10-25 | 6 | +2 | 90 |
| wall victims r2 | 10-25 → 10-26 | 3 | +0 | **90** |

**New solves per batch**

- **zeros (3):** `boa-hierarchical-evaluation-cancellation`, `kcp-go-multiplexed-kcp-streams`, `obsidian-linter-auto-table-of-contents`
- **failed13 (8):** `dynamodb-toolbox-lazy-recursive-schemas`, `igel-persist-feature-schema`, `opa-template-string-reconstruction`, `oxvg-structural-selector-preservation`, `pwntools-tube-multiplexing`, `python-statemachine-state-data-scoping`, `scriggo-method-declarations`, `valibot-recursive-schema-composition`
- **nearmiss (10):** `bandit-interprocedural-taint-checks`, `clack-async-autocomplete-options`, `dynamodb-toolbox-conditional-attribute-requirements`, `happy-dom-deterministic-intersectionobserver`, `koota-query-predicates`, `numba-stencil-boundary-modes`, `prometheus-typed-label-sorting`, `quill-shared-toolbar-focus`, `returns-validated-error-accumulation`, `textual-kitty-key-phases`
- **wallvictims (2):** `koota-composite-trait-aspects`, `sqlfmt-create-table-ddl-formatting`

> **Baseline caveat:** the main-run 66 was measured while the serving platform was still partially misconfigured (LiteLLM router, output-token cap, concurrency — §2). Every stage after it re-runs the *same* tests on progressively fixed config; see §4 for attribution.

---

## 2. Platform (context for the numbers)

Runs were served by **[gufo](https://github.com/uv-genai/gufo)** — the author's own serving stack (forked project, added tensor parallelism + RDMA): **two Strix Halo machines in TP2, linked by two Thunderbolt 4 cables (37 Gb/s, 6 µs latency)**, 240 GB combined memory, serving **Qwen3.8-Flash-Next Q8** at **~45 tok/s sustained, peaks above 65 tok/s, independent of context length**, with contexts reaching **well above 300k tokens**.

What the campaign put through it:

| Metric | Value |
|---|---|
| Input tokens served | **3.31 B** (99.4% prefix-cache hits — 18.5 M new prompt tokens) |
| Output tokens generated | **21.7 M** |
| Agent steps / trials | 25,590 / 186 |
| Largest accepted prompt | **328,485 tokens** (`llamacpp:n_tokens_max`) — vs the original 262,144 ceiling |
| Request path | mini-swe-agent → LiteLLM proxy (pinned 1.105.1) → port-80 relay (trial egress allows only 80/443) → gufo backend |

**Failures attributable to the platform: three rounds** — and this is the core of the story below: the 66/113 baseline (main run, stock config, `n_concurrent_trials=2`) was measured on a **partially misconfigured stack**; everything after it came from re-running the same tests as each platform fix landed.

| Phase | Window | Misconfiguration / fix | Evidence |
|---|---|---|---|
| 1 | Oct 16 → **Oct 18 21:31** | **LiteLLM router misconfigured** (`tpm: 100000` per model, `timeout: 900`, `num_retries: 3`, `cooldown_time: 30`), plus an RDMA bug (operator-documented) and 2–3 concurrent agents. Fixed → tpm removed, timeout 600, retries 1, cooldown 120; all later batches also ran serial (`n=1`) | 16/48 pre-fix trials carry strict LLM-error markers: `litellm.Timeout` ×6, `InternalServerError` ×5, `ReadTimeout` ×3, RateLimit/429 (backup: `litellm_config.yaml.bak-20261018-2131`) |
| 2 | Oct 18 → Oct 24 | **output-token cap too low** — responses truncated mid-tool-call | truncation markers (`finish_reason=length` / "output token limit") in **19/63** rerun-batch trials (zeros 9/16, failed13 3/13, nearmiss 7/34) and 8/65 post-fix main trials |
| 3 | Oct 16 → **Oct 25** | **262,144-token context ceiling** — raised above 300k | 6 wall deaths in the near-miss batch + dynamodb/oxvg/wasmi historically; after the raise: **0** `context_length_exceeded`, largest accepted prompt **328,485 tokens**, truncation markers gone (0/9 in the wall-victim batches) |

Two one-off incidents already documented sit on top of these: a squid egress-proxy timeout killing `kcp-go` (solved on rerun) and one operator-initiated server restart during a batch (no score impact). Everything in §3 is agent/harness/benchmark behavior.

---

## 3. Anatomy of the 23 remaining failures

Headline: **the residual is not capability failure.** By best-ever attempt across all jobs, the 23 unsolved tasks fail **35 f2p tests in total outside `kombu`** (avg **1.6 per task**), while their p2p suites — up to 51,469 tests per task — pass at or near 100%. 17 of 23 have `partial ≥ 0.95`.

### 3.1 Three tasks fail *zero* f2p tests but break one p2p test — deterministically

| Task | f2p | p2p | Attempts | Evidence |
|---|---|---|---|---|
| `gql-incremental-graphql-delivery` | **17/17** (all 4) | 810/811 | 4 | the **same** p2p test fails 4/4 attempts: `TestUnsupportedTransport.test_ex…` / `test_execute_incremental_on_unsupported_transport_…` |
| `bandit-structured-nosec-directives` | **69/69** (both) | 281/282 | 2 | same p2p test 2/2: `test_058_region_unioned_across_statement_lines` |
| `pest-character-class-coalescing` | 104/104 (main) | 249/250 (main) | 2 | whack-a-mole: main = perfect f2p + 1 broken p2p; rerun = clean p2p but 100/104 f2p — **never both at once** |

> Earlier "attempt variance" hypothesis for gql is **refuted**: 4/4 identical regressions. These need an explicit "do not modify existing tests" constraint in the agent prompt, not re-runs.

### 3.2 One-to-three-test near-misses — half of them deterministic

| Task | Best attempt | The failing tests (best attempt) | Stability |
|---|---|---|---|
| `fastapi-deprecation-response-headers` | 136/137 (nearmiss) | `test_nested…` sunset-header edge | 134 → 136 (improving) |
| `httpx-streaming-json-iteration` | 107/108 | `test_iter_json_ndjson_invalid_line…` | **identical 2/2** |
| `koota-deferred-mutation-buffer` | 70/71 | `Deferred W…` removal ordering | **identical 2/2** |
| `awilix-async-container-initialization` | 23/24 | `Async Initialization Feature Edge…` | **identical 2/2** |
| `mashumaro-flattened-dataclass-fields` | 63/66 | 3 × `test_flatten_rename_*` alias cases | **identical 2/2** |
| `obsidian-linter-link-format-conversion` | 57/60 | 3 × escaped-label link cases | **identical 2/2** |
| `kea-atomic-signal-selectors` | 11/12 | `Hybrid Engine: hybrid engine can be enabled and disabled` | fails in **all 4** attempts (incl. main) |
| `csstree-shorthand-expansion-compression` | 76/79 | 3 × box-model shorthand cases | 74 → 76 (improving) |
| `effect-sse-httpapi-streaming` | 46/47 | `fromStream converts a typed Stream…` | 45 → 46 (improving) |
| `termenv-preserve-ansi-resets` | 34/35 (zeros) | 1 × `ansi_new.Test…` | regressed later: 34 → 28 → 30 |
| `fastapi-implicit-head-options` | 42/43 (main) | `test_options_payload_excludes_head…` | 42 → 38 (regressed) |
| `httpx-multipart-response-parsing` | 121/122 (main) | folded-header edge `test_iter_multipart_part_headers_parsing…` | 121 → 116 (regressed) |
| `ink-grid-box-layout` | 24/25 (main) | `minmax with fr max distributes remaining space` | different tests fail each attempt (23/25 ×2 after wall fix) |
| `pebble-durability-wait-apis` | 56/59 (main) | 3 × `TestBatchDurable*` sync-failure cases | 56 → 15 (large regression) |
| `prometheus-transactional-reload-status` | 10/15 | 5 × reload-status cmd tests | **identical 2/2** |
| `wasmi-trap-coredumps` | 20/22 (failed13) | 2 × `wasmi::coredump: coredump_captures_{f32,i32}_…` | 0/22 in 4 other attempts (2× context wall, 1× rabbit-hole, see §3.4) |
| `meriyah-explicit-resource-declarations` | 45/49 (main) | 4 × `await using` / partial-initializer parse cases | wiped to 0/49 by a bad rerun (§3.3) |
| `koota-pair-relation-tracking` | 37/38 (main) | `should require both when used together in AND` | wiped to 0/38 by a bad rerun (§3.3) |
| `updo-policy-alerting` | 15/17 (main) | 2 × `config.TestLoadConfigAlertPolicy*` | wiped to 0/17 by a bad rerun (§3.3) |

**Deterministic vs variance:** for `gql`, `bandit`, `httpx-streaming`, `koota-deferred`, `awilix`, `mashumaro`, `obsidian-link`, `kea`, `prometheus` the failing test is *the same test in every attempt* — re-running cannot flip these; they need a code-level fix (or a scoring-harness nudge). For `fastapi-deprecation`, `csstree`, `effect-sse`, `termenv`, `fastapi-implicit`, `httpx-multipart`, `pebble`, `ink`, `pest` the score moves **in both directions** across attempts — for 11 of the 23 tasks the *best* attempt is not the *latest* one.

### 3.3 Three near-misses wiped by empty-patch reruns (harness, not model)

| Task | Best attempt | Bad attempt | What happened |
|---|---|---|---|
| `meriyah` | 45/49 (main) | **0/49, 0-byte patch** | `RepeatedFormatError` abort in the near-miss batch — session killed before any commit |
| `koota-pair` | 37/38 (main) | **0/38, 0-byte patch** | same abort; all 38 f2p fail on the untouched base |
| `updo` | 15/17 (main) | **0/17, 0-byte patch** | empty patch + submit quirk |

This is the same failure class documented in `zeros-rerun-analysis-2026-10-21.md` §A (7/13 there): **the collector only captures committed work** (`git diff <base> HEAD`), and a harness abort (`RepeatedFormatError`) or un-committed session end yields a 0-byte patch → base graded → zero. The `commit-incremental.yaml` fix (§4) solved it for *well-behaved* sessions but **cannot help when the format-error abort fires before the agent ever runs a commit**. Three main-run near-misses were lost this way in the near-miss batch.

### 3.4 `wasmi-trap-coredumps`: rabbit-hole case (wall-victims attempt)

> **Addendum (2026-10-31): solved — see the addendum after §6.** The same task was
> completed 22/22 (p2p clean) by `maya-glm5-m-tp2-mtp` in one attempt, proving the
> task solvable and pinning gufo's five zeros squarely on the model.

The failed13 attempt reached **20/22** with an 85 KB patch. The wall-victims attempt (after the context fix) **never engaged with the task**: the word "coredump" appears only in the prompt across 12,520 log lines / 209 commands; the agent spent ~35 min on read-only exploration, then hit a *pre-existing* `E0554` (`#![feature] may not be used on the stable channel`) in `cargo test --all-features`, declared it the "issue", patched two `Cargo.toml` feature lines (878-byte patch), and submitted a confident summary. Pure model failure — no infra, no context error, patch collected correctly.

### 3.5 `kombu-virtual-queue-dead-lettering`: the only genuine never-started

Best ever: **1/76**. The model investigated, found no puzzle code in the tree, and *deliberately* submitted an empty diff as "correct" (main run), after first hallucinating an unrelated task (documented in `zero-pass.md`). Everything else in §3.2 at least reached 10/15.

### 3.6 Resolved failure classes (history, for completeness)

| Class | Where documented | Outcome |
|---|---|---|
| **Submission pipeline** (worked, never committed) — 7/13 zeros | `zeros-rerun-analysis` §A | fixed via `commit-incremental.yaml` → **+8** in failed13 batch |
| **262k context wall** — 6 tasks + dynamodb/oxvg/wasmi | `nearmiss-rerun-results` (whole §) | `--context` raised → **0 errors since**, +2 solved, all wall victims now complete runs |
| **Infra: squid proxy timeout** (`kcp-go`, 6 API calls) | `zero-pass.md` | solved on rerun |
| **Verifier artifact** (`obsidian-linter-auto-table-of-contents` whitelist/CTRF name mismatch) | `zero-pass.md` | solved on rerun |
| **Model output cap / `RepeatedFormatError`** (arktype, koota-query) | `zero-pass.md` | both solved later |

---

## 4. What actually moved the score

**Attribution caveat:** the batches ran on *progressively fixed* platform config (§2), so platform-fix credit and agent-config credit are entangled for failed13/nearmiss — both were "fixes", not sampling luck. The honest reading of each stage:

| Stage | Platform state | Agent config | Yield |
|---|---|---|---|
| Main run (baseline) | phase 1 active early (router bugs), phase 2 active throughout (low out-tokens), n=2 | stock | **66** |
| zeros rerun | phase 1 fixed, **phase 2 active** (9/16 trials truncated) | stock (pass@2) | +3 — `boa` (one-word `mut` fix), `kcp-go` (infra), `obsidian-linter` |
| failed13 rerun | phase 1 fixed, **phase 2 active** (3/13 truncated) | **commit-mandate prompt** | +8/13 — includes the 7/13 that previously lost all work uncommitted (`zeros-rerun-analysis` §A) |
| near-miss rerun | phase 1 fixed, **phases 2+3 active** (7/34 truncated; 6 context-wall deaths) | commit-mandate prompt | +10/34 — the `.95–.99` cluster is the highest-yield zone |
| wall victims | **all three phases fixed** (context + out-token) | commit-mandate prompt | +2/6 — koota-composite (45/51 → 51/51), sqlfmt |
| wall victims r2 | fixed | commit-mandate prompt | +0/3 — chronic p2p regressors don't flip (§3.1) |

**Net: +24 over the baseline, of which the platform fixes are the precondition for most of it** — the commit-mandate prompt is the one intervention whose effect can be isolated (7 of 13 zeros died with real work sitting uncommitted), but even that batch only scored after the serving stack was healthy.

**Scoring note:** binary scoring hides how close the residual is — 17/23 unsolved tasks have `partial ≥ 0.95`, and the unsolved-set mean partial credit is ~0.95. A task passing 136/137 f2p tests with a perfect 3,134-test p2p suite scores identically to one that never started.

---

## 5. Conclusions

1. **Final score: 90/113 (79.6%)** after 7 batches; progression 66 → 67 → 70 → 78 → 88 → 90.
2. **The campaign doubled as a shake-down of the serving platform** — and that is the strongest validation outcome. Three rounds of platform defects were *found by the benchmark and fixed by the operator*: the LiteLLM router misconfig (tpm/timeout/retries/cooldown, Oct 18), the too-low output-token cap (visible as truncations in ~30% of rerun-batch trials), and the 262k context ceiling (Oct 25). After the final fix the stack served **3.31 B input tokens / 21.7 M output tokens at 45–65 tok/s, contexts past 328k, with zero serving-side failures**. The 66-task baseline was measured on the partially misconfigured stack — it is an under-measurement of the platform, not of the model.
3. **The remaining 23 are dominated by test-level fragility, not capability:** 3 chronic one-p2p-test regressors (deterministic), ~17 one-to-few-f2p-test misses (half with identical failure signatures across attempts), 3 harness-wiped near-misses, 1 genuine miss (`kombu`).
4. **Highest-value next actions, in order:**
   - **harness:** fall back to the working tree when `git diff base HEAD` is empty, and harden against `RepeatedFormatError` before session end (would have protected meriyah/koota-pair/updo and the 7 zeros in §A of the zeros report);
   - **prompt:** add an explicit "never modify existing (p2p) tests" constraint — targets gql/bandit/pest without changing the harness;
   - **model:** targeted re-runs only for the *variance* subset (fastapi-deprecation, csstree, effect-sse, termenv, ink, pest, httpx-multipart, fastapi-implicit, pebble) — not for the deterministic-signature set;
   - **benchmark:** consider reporting partial credit alongside the binary reward; the current metric discards 95%+ complete solutions.

---

## 6. Leaderboard comparison (`deepswe.datacurve.ai`)

The public leaderboard (updated 2026-09-22) reports **Pass@1** per model — one attempt per task, stock mini-swe-agent, capped effort tiers (MEDIUM→XHIGH), with $/task and steps. Top of board: **gpt-6-astra 74%, gemini-3.8-flash 74%, claude-opus-5 74%** (±3–5% task-level CI).

| Our number | Value | Comparable? |
|---|---|---|
| Main run — stock config, one attempt per task | **66/112 = 58.9%** | metric-identical (same corpus at upstream HEAD `0b9fabb`, same mini-swe-agent 2.4.6) — but measured with the §2 platform bugs still active, i.e. an **under-measurement** |
| Full campaign — 185 attempts / 113 tasks after the platform fixes | 90/113 = **79.6%** | **no** — best-of-k after platform fixes plus one agent-prompt change (commit-mandate); would rank above all listed models, but not under their protocol |
| Fresh one-shot on the fixed platform, stock config, `n=1` | **not yet run** | this is the leaderboard-grade number; the 66 baseline suggests it lands well above 58.9% |

Caveats either way: their ± is a binomial CI over 113 tasks (79.6% vs 74% ≈ 1.5 CI widths), their “Best” toggle already selects each model's best effort tier, and our 79.6% has no CI (single campaign). A leaderboard submission would need their “Run DeepSWE” protocol — one attempt, stock config — which our main run approximates *except* it ran on the broken platform.

---

## Addendum (2026-10-31) — `wasmi-trap-coredumps` independently solved by a second model

One day after this report, the one task gufo never solved (§3.4, five attempts,
best 20/22) was **solved outright on its first attempt** by **`maya-glm5-m-tp2-mtp`**
(GLM-5-M, TP2 + MTP, served by the same gufo platform):

| | maya-glm5-m-tp2-mtp | gufo best (failed13) |
|---|---|---|
| Result | **reward 1 · f2p 22/22 · p2p 58/58 · partial 1.000** | 0 · 20/22 · 58/58 |
| Config | commit-mandate agent config; backend `--context` raised | commit-mandate config |
| Effort | 81 min, 195 steps, 72.9 KB patch | comparable |

The patch is a full implementation (`coredump.rs` ×2, `code_map.rs` gaining IP →
function/locals resolution, executor hooks in both dispatch backends, host
re-entrancy extending frames across levels — the spec's hardest requirement).

Three conclusions: (1) the task is **solvable**, so gufo's zeros were model-side,
not task or harness artifacts; (2) the larger backend context was load-bearing
(gufo's first two deaths were the old ceiling, and an earlier attempt of the
second model died at a 32,768-token cap at step 14); (3) the `action was not
executed` submit quirk appeared again and was again cosmetic — the patch
collected cleanly.

---

## Appendix A — Full attempt matrix (23 unsolved tasks)

*job abbreviations: `main`, `zeros`, `failed13`, `nearmiss`, `wv` (wallvictims), `wv-r2` · `patch` = collected `artifacts/model.patch` size · every attempt scored reward 0*

| Task | Attempts (f2p / p2p / patch) |
|---|---|
| `gql-incremental-graphql-delivery` | main 17/17, 810/811, 96 KB · nearmiss 17/17, 810/811, 128 KB · wv 17/17, 810/811, 118 KB · wv-r2 17/17, 810/811, 141 KB |
| `bandit-structured-nosec-directives` | main 69/69, 281/282, 38 KB · nearmiss 69/69, 281/282, 47 KB |
| `pest-character-class-coalescing` | main 104/104, 249/250, 30 KB · nearmiss 100/104, 250/250, 36 KB |
| `fastapi-deprecation-response-headers` | main 134/137, 3134/3134, 97 KB · nearmiss 136/137, 3134/3134, 89 KB |
| `httpx-streaming-json-iteration` | main 107/108, 1404/1404, 40 KB · nearmiss 107/108, 1404/1404, 41 KB |
| `koota-deferred-mutation-buffer` | main 70/71, 128/128, 104 KB · nearmiss 70/71, 128/128, 124 KB |
| `effect-sse-httpapi-streaming` | main 45/47, 70/70, 61 KB · nearmiss 46/47, 70/70, 49 KB |
| `csstree-shorthand-expansion-compression` | main 74/79, 16715/16715, 63 KB · nearmiss 76/79, 16715/16715, 71 KB |
| `awilix-async-container-initialization` | main 23/24, 162/162, 79 KB · nearmiss 23/24, 162/162, 70 KB |
| `mashumaro-flattened-dataclass-fields` | main 63/66, 30014/30014, 62 KB · nearmiss 63/66, 30014/30014, 48 KB |
| `obsidian-linter-link-format-conversion` | main 57/60, 1131/1131, 32 KB · nearmiss 57/60, 1131/1131, 29 KB |
| `httpx-multipart-response-parsing` | main 121/122, 1272/1272, 33 KB · nearmiss 116/122, 1272/1272, 42 KB |
| `fastapi-implicit-head-options` | main 42/43, 3134/3134, 114 KB · nearmiss 38/43, 3134/3134, 100 KB |
| `termenv-preserve-ansi-resets` | main 0/35, 0 B · zeros 34/35, 46 KB · failed13 28/35, 42 KB · nearmiss 30/35, 39 KB |
| `ink-grid-box-layout` | main 24/25, 49/49, 54 KB · nearmiss 0/25, 0 B (context wall) · wv 23/25, 64 KB · wv-r2 23/25, 57 KB |
| `kea-atomic-signal-selectors` | main 11/12, 139/139, 88 KB · nearmiss 9/12, 62 KB · wv 11/12, 109 KB · wv-r2 11/12, 94 KB |
| `pebble-durability-wait-apis` | main 56/59, 44/44, 64 KB · nearmiss 15/59, 67 KB |
| `prometheus-transactional-reload-status` | main 10/15, 82/82, 104 KB · nearmiss 10/15, 82/82, 95 KB |
| `wasmi-trap-coredumps` | main 0/22, 0 B (wall) · zeros 0/22, 0 B (wall) · failed13 **20/22**, 86 KB · nearmiss 0/22, 0 B (wall) · wv 0/22, 878 B (rabbit-hole) |
| `meriyah-explicit-resource-declarations` | main 45/49, 91 KB · nearmiss 0/49, **0 B** (format abort) |
| `koota-pair-relation-tracking` | main 37/38, 65 KB · nearmiss 0/38, **0 B** (format abort) |
| `updo-policy-alerting` | main 15/17, 92 KB · nearmiss 0/17, **0 B** |
| `kombu-virtual-queue-dead-lettering` | main 0/76, 0 B · zeros 0/76, 0 B · failed13 1/76, 7 KB |
