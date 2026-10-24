# DeepSWE — Near-Miss Batch: Results & Final Corpus Status

**Job:** `jobs/deepswe-gufo-qwen3.8-flash-next-tp2-q8-nearmiss-rerun`
*(run via `rerun-nearmiss.sh --incremental`; 34 tasks, `--n-concurrent 1`, commit-incremental agent config)*
**Model:** `gufo-qwen3.8-flash-next-tp2-q8` · Pier + mini-swe-agent 2.4.6 (litellm 1.105.1 pinned)
**Finished:** 2026-10-24 18:41 · **Report date:** 2026-10-24
**Companion report:** `zeros-rerun-analysis-2026-10-21.md`

---

## Run status: complete ✅

- **Pier: idle** (no processes), job finished `2026-10-24 18:41`, **34/34 graded**, 0 unfinished
- Batch score: **10 solved / 34**
- **Unique corpus: 88/113 solved (77.9%)**
  - 66 (main job) → +1 arktype standalone → +3 (zeros rerun) → +8 (failed13, incremental commits) → **+10 (this batch) = 88**

Task selection for this batch was computed from each task's **latest attempt across
all same-model jobs**, which correctly pulled in the four near-misses created by the
failed13 batch (`koota-composite` 45/51, `koota-query` 41/43, `wasmi` 20/22,
`termenv` 28/35) and excluded everything already solved.

## The 6 errored trials: one single cause — the context wall

All six are `NonZeroAgentExitCodeError` **with the 262k context wall in their logs**
— no infrastructure, no format errors, no proxy problems:

| Trial | f2p | Note |
|---|---|---|
| `gql-incremental-graphql-delivery` | **1.0** | Died at the wall — and it's the chronic p2p-regressor, so still reward 0 |
| `ink-grid-box-layout` | 0.0 | Died at the wall |
| `kea-atomic-signal-selectors` | 0.75 | Died at the wall mid-work |
| `koota-composite-trait-aspects` | 0.0 | Died at the wall (prior attempt was 45/51) |
| `sqlfmt-create-table-ddl-formatting` | 0.0 | Died at the wall |
| `wasmi-trap-coredumps` | 0.0 | Died at the wall (prior attempt was 20/22) |

The error text: `prompt exceeds the 262144-token context; increase --context or
shorten the conversation` (HTTP 400 `context_length_exceeded`, retried futilely by
the client).

> Note: `koota-composite` and `wasmi` appear regressed only because the "latest
> attempt" view reflects this batch's wall-deaths — their prior attempts were far
> better. The context ceiling is now **the dominant remaining failure mode**: 6 of 25
> unsolved died on it here, plus dynamodb/oxvg/wasmi historically.

## Remaining 25 unsolved, by class

| Class | Count | Members / detail |
|---|---|---|
| **Context-wall casualties (262k)** | **6** | `gql-incremental`, `ink-grid`, `kea`, `koota-composite`, `sqlfmt`, `wasmi` — *would likely flip with a larger backend `--context`* |
| **f2p = 100% but p2p regression** | 2 | `bandit-structured-nosec-directives`, `gql-incremental-graphql-delivery` — each breaks exactly one pre-existing test (gql also appears above) |
| **True near-misses (0.85–0.99)** | 10 | `fastapi-deprecation` 0.99 · `httpx-streaming-json` 0.99 · `koota-deferred` 0.99 · `effect-sse` 0.98 · `pest-character-class` 0.96 · `csstree-shorthand` 0.96 · `awilix-async` 0.96 · `httpx-multipart` 0.95 · `mashumaro-fields` 0.95 · `obsidian-link-format` 0.95 |
| **Mid (0.25–0.88)** | 4 | `fastapi-implicit` 0.88 · `termenv-preserve-ansi` 0.86 · `prometheus-transactional-reload` 0.67 · `pebble-durability` 0.25 |
| **Hard zeros (≈0)** | 6 | `kombu-virtual-queue` 0.013 (deliberate empty submission) · `koota-pair` 0.0 · `meriyah-explicit` 0.0 · `sqlfmt` 0.0 (wall) · `updo-policy-alerting` 0.0 · `ink-grid` 0.0 (wall) |

*(Counts overlap by one: `gql` is both a wall casualty and a p2p-regressor.)*

## The clear next lever

**Raise `--context` above 262,144 on the gufo backend.** The six wall-deaths are
deterministic — rerunning them unchanged reproduces the same result. Memory note for
the operator: strix-halo-1 sat at ~74% RAM with the current context; KV growth for a
larger window must fit alongside it (240 GB pair total).

After that, one more targeted batch over the wall victims would realistically push
the corpus toward **95+/113**.

## Progress across all batches (unique tasks solved)

| Stage | Solved |
|---|---|
| Main 113-task run | 66 |
| + arktype standalone | 67 |
| + zeros rerun (incremental-commit analysis batch) | +3 → 70 |
| + failed13 rerun (`--incremental`) | +8 → 78 |
| + near-miss rerun (`--incremental`) | +10 → **88 / 113 (77.9%)** |
