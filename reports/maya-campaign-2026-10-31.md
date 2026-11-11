# Maya campaign — re-running the DeepSWE failed-task set on GLM-5 (S/M/L) and DeepSeek v4.1 Flash

**Started:** 2026-10-31 · **Companion:** `final-report-2026-10-26.md` (gufo Qwen3.8 campaign, 90/113)
**Task set:** the **23 tasks unsolved** by `gufo-qwen3.8-flash-next-tp2-q8` (final report §3 + Appendix A) — includes the 3 harness-wiped near-misses, the 3 chronic p2p-regressors, and `kombu`
**Platform:** same gufo serving stack (two Strix Halo, TP2, Thunderbolt 4), backend `--context` raised (>300k), platform frozen
**Models (6 GLM arms):** `maya-glm5-{s,m,l}-tp2` and `maya-glm5-{s,m,l}-tp2-mtp` (GLM-5 at 3 sizes, ± MTP speculative decoding)
**DeepSeek arms:** `maya-deepseek-xs` = DeepSeek v4.1 Flash **Q1**, `maya-deepseek-s` = DeepSeek v4.1 Flash **Q2/3** — project [mw00/project-maya](https://github.com/mw00/project-maya)

## Protocol conventions

- One job per model; tasks run from the static failed-23 list (`scripts/rerun-subset.sh failed23`, `MODEL=maya-…`)
- Agent config: commit-mandate (`commit-incremental.yaml`) unless a row says *stock*
- Attempt 1 per model per task = **pass@1**; any re-run makes that cell best-of-k and must be marked `(k=n)`
- Grading identical to the gufo campaign: binary `reward`, `f2p`/`p2p` explain misses
- A cell counts solved only when `reward = 1`

## Results matrix

Reference column = **gufo best attempt** across its 5–6 batches (Appendix A of the companion report).

| Task | gufo best (f2p / p2p) | maya-s | maya-s-mtp | maya-m | maya-m-mtp | maya-l | maya-l-mtp | ds-xs (Q1) | ds-s (Q2/3) |
|---|---|---|---|---|---|---|---|---|---|
| `awilix-async-container-initialization` | 23/24 · 162/162 | | | | | | **23/24 · 162/162** | 23/24 · 162/162 | **24/24 ✅ reward 1** |
| `bandit-structured-nosec-directives` | 69/69 · p2p 281/282 | | | | | | |
| `csstree-shorthand-expansion-compression` | 76/79 · 16715/16715 | | | | | | |
| `effect-sse-httpapi-streaming` | 46/47 · 70/70 | | | | **47/47 ✅** (solo, 11-11) | | | | |
| `fastapi-deprecation-response-headers` | 136/137 · 3134/3134 | | | | | | |
| `fastapi-implicit-head-options` | 42/43 · 3134/3134 | | | | | | |
| `gql-incremental-graphql-delivery` | 17/17 · p2p 810/811 | | | | | | |
| `httpx-multipart-response-parsing` | 121/122 · 1272/1272 | | | | | | |
| `httpx-streaming-json-iteration` | 107/108 · 1404/1404 | | | | | | | | **108/108 ✅** (solo, 11-11) |
| `ink-grid-box-layout` | 24/25 · 49/49 | | | | | | |
| `koota-deferred-mutation-buffer` | 70/71 · 128/128 | | | | | | |
| `kea-atomic-signal-selectors` | 11/12 · 139/139 | | | | | | |
| `koota-pair-relation-tracking` | 37/38 · 172/172 | | | | | | |
| `mashumaro-flattened-dataclass-fields` | 63/66 · 30014/30014 | | | | | | |
| `meriyah-explicit-resource-declarations` | 45/49 · 51469/51469 | | | | | | |
| `obsidian-linter-link-format-conversion` | 57/60 · 1131/1131 | | | | | | |
| `pest-character-class-coalescing` | 104/104 · p2p 249/250 | | | | | | |
| `pebble-durability-wait-apis` | 56/59 · 44/44 | | | | | | |
| `prometheus-transactional-reload-status` | 10/15 · 82/82 | | | | | | |
| `termenv-preserve-ansi-resets` | 34/35 · 87/87 | | | | | | |
| `updo-policy-alerting` | 15/17 · 123/123 | | | | | | | | **17/17 ✅** (solo, 11-10) |
| `kombu-virtual-queue-dead-lettering` | 1/76 · 1412/1412 | | | | | | |
| `wasmi-trap-coredumps` | **22/22 ✅** (attempt 7, 11-07) | | **22/22 ✅** | | **22/22 ✅** | | **22/22 ✅** | | **22/22 ✅** (solo, 11-10) |

## Datapoint 1 — `wasmi-trap-coredumps` SOLVED by all three sizes (2026-10-31)

The one task gufo never solved in five attempts (best 20/22) was completed
**22/22 f2p, 58/58 p2p, partial 1.000 on the first attempt by every size** —
`maya-glm5-{s,m,l}-tp2-mtp`, commit-mandate config, raised backend context:

| | maya-**s**-mtp | maya-**m**-mtp | maya-**l**-mtp | gufo (reference) |
|---|---|---|---|---|
| Result | **reward 1** | **reward 1** | **reward 1** | 0 · best 20/22 |
| Duration | 163 min | 81 min | 100 min | — |
| Steps | 308 | 195 | 227 | 195–209 (gufo attempts) |
| Input tokens | **73.5 M** | 24.7 M | 28.7 M | 24.3 M (single attempt) |
| Output tokens | **185.9 k** | 92.8 k | 94.4 k | 93.6 k |
| Cache hit | 99.5% | 99.2% | 99.3% | 99.3% |
| Patch | 98 KB | 71 KB | 68 KB | 85 KB (failed13) |
| f2p / p2p fails | 0 / 0 | 0 / 0 | 0 / 0 | 2 / 0 (failed13) |

**Token efficiency — the notable finding.** The S model is markedly less
sample-efficient than M/L on this task: **2.0× the output tokens** of M (185.9 k vs
92.8 k — not +50%) and **3.0× the input tokens** (73.5 M vs 24.7 M), for 1.6× the
steps and 2.0× the wall time. L, by contrast, tracks M almost exactly (+1.7%
output, +16% input/steps, +23% time) — the bigger model costs essentially nothing
extra per solve here. All three left p2p untouched (no chronic-regressor behaviour
on this task), and the patch sizes converge on the same implementation shape.

Cross-ref: final report addendum (2026-10-31) for the implementation anatomy.
Note: an earlier M attempt died at a 32,768-token backend cap (step 14) — the
raised `--context` is load-bearing for all of these runs.

Implications for the campaign: the residual task set is solvable in principle —
now by **three different models on the first try**, so gufo's five zeros were
model-side. Watch specifically for:
- **chronic p2p regressors** (`gql`, `bandit`, `pest`) — did another model also break the
  same test, or is that a gufo-specific failure?
- **the 3 wiped near-misses** (`meriyah`, `koota-pair`, `updo`) — gufo's best attempts
  were 45/49, 37/38, 15/17; a clean first attempt on a healthy platform should score there.
- **deterministic-signature misses** (kea's hybrid-engine toggle, httpx-streaming's ndjson
  line, awilix/mashumaro/obsidian-link single cases) — identical failing tests across gufo
  attempts; a second model missing them the same way would suggest task/verifier edges.

## Datapoint 2 — `awilix` SOLVED by DeepSeek v4.1 Flash at **Q2/3**, beating Qwen3.8 at Q8 (2026-11-04)

The single edge test that three earlier attempts missed *identically* —
`…Edge cases and integration allows scope.initialize() without calling
parent.initialize() first` — was passed by the DeepSeek Q2/3 arm on its first try:

| Attempt | Model / bits | Result | Effort | Exception |
|---|---|---|---|---|
| **2026-11-04** | **`maya-deepseek-s` — DeepSeek v4.1 Flash Q2/3** | ✅ **24/24 · partial 1.000 · reward 1** | 54 min, 74 steps, 51 KB, 83.6 k out | none |
| 2026-11-03 | `maya-deepseek-xs` — DeepSeek v4.1 Flash **Q1** | ❌ 23/24 · 0.9946 | 51 min, 55 steps, 40 KB, 62.4 k out | none |
| 2026-10-31 | `maya-glm5-m-tp2-mtp` | ❌ 23/24 · 0.9946 | 46 min, 80 steps, 57 KB, 62.5 k out | none |
| gufo campaign ×2 | `gufo-qwen3.8-flash-next-tp2-q8` (**Q8**) | ❌ 23/24 · 0.9946 (both) | main + nearmiss | none |
| 2026-11-02/03 | `maya-glm5-l-tp2-mtp` | ❌ 0/24 (infra: pre-fix timeouts) | 2 attempts killed by a single **792 s** request vs the old `timeout: 600` | read-timeouts |
| 2026-11-04 | `maya-glm5-l-tp2-mtp` **rerun, post-fix** | ❌ **23/24 · 0.9946** (same edge test) | 61 min, 74 steps, 77.7 k out | **none** — the 792 s-class request completed under the new 1800 s timeout |

**Findings:**

1. **First-ever solve of this task** — and the head-to-head is the campaign's
   sharpest so far: **Qwen3.8-Flash-Next at Q8 failed it twice; DeepSeek v4.1
   Flash at Q2/3 passed it first try.** Even the Q1 arm reached 23/24 with the
   same single miss as gufo/GLM-m, so the model finds the edge at a bit depth
   where the Q8 competitor does not.
2. **Revises the earlier classification.** awilix was filed as "task-edge, not a
   discriminator" when gufo and GLM-m failed identically — the DeepSeek arms
   show it *does* discriminate: model family/capability decides whether the edge
   is found, while **bit depth tracks cost, not outcome** (consistent with the
   wasmi S-vs-M token gap: ds-s spent 34% more output than GLM-m for its solve,
   and Q1 xs still scored 23/24).
3. **Clean runs on every arm since the 2026-11-03 hardening** (both DeepSeek arms,
   and the GLM-L rerun whose earlier deaths were traced to a single **792-second**
   request against the old 600 s timeout — with litellm at 1800 s it completes and
   the task scores normally). The timeout class is fixed end to end.

## Log

| Date | Event |
|---|---|
| 2026-10-31 | campaign started; `maya-glm5-m-tp2-mtp` first single-task run (wasmi) solved 22/22 |
| 2026-10-31 | wasmi also solved by `maya-glm5-s-tp2-mtp` and `maya-glm5-l-tp2-mtp` — all three sizes pass 22/22; S used 2× output / 3× input tokens of M |
| 2026-11-03 | `maya-deepseek-xs` (DeepSeek v4.1 Flash **Q1**) awilix 23/24 — same single edge test as gufo/GLM-m |
| 2026-11-04 | **awilix solved by `maya-deepseek-s` (Q2/3): 24/24, partial 1.000** — first solve; beats gufo Q8 and GLM-m on the task |
| 2026-11-04 | GLM-5.3 `maya-glm5-l-tp2-mtp` awilix rerun clean (no timeouts): 23/24, same edge test — prior zeros were the 792 s request vs the old 600 s litellm timeout |
| 2026-11-07 | **gufo itself solved wasmi on attempt 7** (22/22, clean) → corpus 91/113; the task is no longer a gufo residual |
| 2026-11-10 | **deepseek-s-mtp `failed23` arm complete: 23/23 graded, 10 solved** (awilix, csstree, effect-sse, fastapi-implicit, httpx-multipart, kombu, koota-deferred, mashumaro, obsidian-link, prometheus) — its wasmi attempt died on a **context wall (prompt 262,222 > 262,144)**: that deployment still runs the old ceiling |
| 2026-11-10 | **deepseek-s (Q2/3) solo reruns both pass:** wasmi **22/22** (99 min, 150 steps) and updo **17/17** (56 min, 73 steps) — replacing the batch's 0/22 context-wall death |
| 2026-11-11 | **glm5-m solo effect-sse: 47/47 ✅** (180 min, 221 steps) after its batch attempt graded 0; glm-m `failed23` arm finished **22/22 graded (9 solved)** — full three-arm analysis: `failed23-arm-comparison-2026-11-10.md` |
| 2026-11-11 | **deepseek-s solo httpx-streaming: 108/108 ✅** (64 min, 84 turns, 93.3 k out, p2p 1404/1404) — the ndjson edge that failed every arm; 23-set now **17/23 solved, 6 open** |
| 2026-11-07 | **gufo Q4 same-weights A/B:** wasmi ✅ 22/22 (69 min, 250 steps), awilix 23/24 same edge test — outcomes identical to Q8, cost +20–40 % tokens at ~20 % faster decode (`model-comparison-2026-11-04.md` §1.1/§3) |
