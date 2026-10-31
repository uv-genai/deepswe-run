# Maya campaign — re-running the DeepSWE failed-task set on GLM-5 (S/M/L)

**Started:** 2026-10-31 · **Companion:** `final-report-2026-10-26.md` (gufo Qwen3.8 campaign, 90/113)
**Task set:** the **23 tasks unsolved** by `gufo-qwen3.8-flash-next-tp2-q8` (final report §3 + Appendix A) — includes the 3 harness-wiped near-misses, the 3 chronic p2p-regressors, and `kombu`
**Platform:** same gufo serving stack (two Strix Halo, TP2, Thunderbolt 4), backend `--context` raised (>300k), platform frozen
**Models (6):** `maya-glm5-{s,m,l}-tp2` and `maya-glm5-{s,m,l}-tp2-mtp` (GLM-5 at 3 sizes, ± MTP speculative decoding)

## Protocol conventions

- One job per model; tasks run from the static failed-23 list (`scripts/rerun-subset.sh failed23`, `MODEL=maya-…`)
- Agent config: commit-mandate (`commit-incremental.yaml`) unless a row says *stock*
- Attempt 1 per model per task = **pass@1**; any re-run makes that cell best-of-k and must be marked `(k=n)`
- Grading identical to the gufo campaign: binary `reward`, `f2p`/`p2p` explain misses
- A cell counts solved only when `reward = 1`

## Results matrix

Reference column = **gufo best attempt** across its 5–6 batches (Appendix A of the companion report).

| Task | gufo best (f2p / p2p) | maya-s | maya-s-mtp | maya-m | maya-m-mtp | maya-l | maya-l-mtp |
|---|---|---|---|---|---|---|---|
| `awilix-async-container-initialization` | 23/24 · 162/162 | | | | | | |
| `bandit-structured-nosec-directives` | 69/69 · p2p 281/282 | | | | | | |
| `csstree-shorthand-expansion-compression` | 76/79 · 16715/16715 | | | | | | |
| `effect-sse-httpapi-streaming` | 46/47 · 70/70 | | | | | | |
| `fastapi-deprecation-response-headers` | 136/137 · 3134/3134 | | | | | | |
| `fastapi-implicit-head-options` | 42/43 · 3134/3134 | | | | | | |
| `gql-incremental-graphql-delivery` | 17/17 · p2p 810/811 | | | | | | |
| `httpx-multipart-response-parsing` | 121/122 · 1272/1272 | | | | | | |
| `httpx-streaming-json-iteration` | 107/108 · 1404/1404 | | | | | | |
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
| `updo-policy-alerting` | 15/17 · 123/123 | | | | | | |
| `kombu-virtual-queue-dead-lettering` | 1/76 · 1412/1412 | | | | | | |
| `wasmi-trap-coredumps` | 20/22 · 58/58 | | | **22/22 · 58/58 ✅ reward 1** (attempt 1; see below) | | | |

## Datapoint 1 — `wasmi-trap-coredumps` SOLVED by maya-glm5-m-tp2-mtp (2026-10-31)

The one task gufo never solved in five attempts (best 20/22) was completed **22/22,
p2p 58/58, partial 1.000 on the first attempt**: 81 min, 195 steps, 72.9 KB patch
(implementation spans `coredump.rs` ×2, `code_map.rs` IP→function/locals resolution,
executor hooks in both dispatch backends, host re-entrancy frame extension).
An earlier attempt of the same model died at a 32,768-token backend cap (step 14) —
the raised `--context` is load-bearing. Cross-ref: final report addendum (2026-10-31).

Implications for the campaign: the residual task set is solvable in principle; gufo's
zeros were model-side. Watch specifically for:
- **chronic p2p regressors** (`gql`, `bandit`, `pest`) — did another model also break the
  same test, or is that a gufo-specific failure?
- **the 3 wiped near-misses** (`meriyah`, `koota-pair`, `updo`) — gufo's best attempts
  were 45/49, 37/38, 15/17; a clean first attempt on a healthy platform should score there.
- **deterministic-signature misses** (kea's hybrid-engine toggle, httpx-streaming's ndjson
  line, awilix/mashumaro/obsidian-link single cases) — identical failing tests across gufo
  attempts; a second model missing them the same way would suggest task/verifier edges.

## Log

| Date | Event |
|---|---|
| 2026-10-31 | campaign started; `maya-glm5-m-tp2-mtp` first single-task run (wasmi) solved |
