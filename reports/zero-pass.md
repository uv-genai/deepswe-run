# DeepSWE Zero-Pass (f2p = 0/..) Report

**Job:** `jobs/deepswe-gufo-qwen3.8-flash-next-tp2-q8`
**Model:** `openai/gufo-qwen3.8-flash-next-tp2-q8`
**Graded:** 66 trials — 38 solved (57.6%) — 8 zero-pass trials (`f2p_passed == 0`)

Zero pass = the agent passed **none** of the fail-to-pass tests. Per-task deep
dives are in `analysis-<task>.md` files in this folder. Root causes:

## Summary table

| Task | f2p | Patch | Root cause | Category |
|------|-----|-------|-----------|----------|
| arktype-json-schema-refs-depende | 0/25 | 0 B | `RepeatedFormatError` (5× output-token-limit), no commits | Model output cap |
| boa-hierarchical-evaluation-canc | 0/17 | 78 KB | Patch **breaks lib-test compilation** (E0596), rc=101, no JUnit | Genuine failure (poor final verification) |
| dynamodb-toolbox-lazy-recursive | 0/37 | 0 B | `context_length_exceeded` (262k) after 162 calls, no commits | Context limit |
| kcp-go-multiplexed-kcp-streams | 0/30 | 0 B | litellm **timeouts via squid proxy** after 6 calls (`--exit-immediately`) | Infra/network |
| kombu-virtual-queue-dead-letteri | 0/76 | 0 B | Model **hallucinated a different task** (19 unparseable outputs, 18 calls) | Model malfunction |
| koota-composite-trait-aspects | 0/51 | 0 B | `context_length_exceeded` (262k) after 152 calls, no commits | Context limit |
| koota-query-predicates | 0/43 | 0 B | `RepeatedFormatError` (3× output-token-limit), no commits | Model output cap |
| obsidian-linter-auto-table-of-co | 0/41 | 49 KB | **Verifier name-mismatch**: jest passed 38/41 but all recorded "missing from report"; 3 real test bugs | Verifier artifact (+ minor real bugs) |

## Categories

### Context/output limits (4 trials)
`arktype`, `dynamodb-toolbox`, `koota-composite`, `koota-query` — all died from
the 262k context window or the per-response output token cap, with **zero commits**,
so real work was lost. Fix: context truncation/compaction and/or higher
`max_output_tokens`; consider auto-committing the working tree at trial end.

### Infra/network (1 trial)
`kcp-go` — squid egress proxy read timeouts against the local LLM endpoint killed
the trial after 6 API calls. Pure rerun candidate; check server health for the
affected window (2026-10-18 ~16:53 UTC).

### Model malfunction (1 trial)
`kombu` — the model hallucinated an unrelated task (`cplit.py` in
`/home/parker/projects/workspace`) and never produced a parseable tool call.
Rerun; investigate if it recurs.

### Verifier artifact (1 trial)
`obsidian-linter` — jest passed 38/41 f2p, but the verifier whitelist names
("Auto Table of Contents …") don't match the CTRF names ("Table of Contents
Generator …") → all 41 "missing from report". Benchmark-side naming bug; no agent
can pass this task as scored. 3 genuine failures exist anyway (heading `{#id}` /
trailing `#` not stripped from TOC link text), so true f2p = 38/41.

### Genuine solution failure (1 trial)
`boa` — real 78 KB patch committed, but it introduced a Rust compile error in a
lib test (`E0596` at `core/engine/src/tests/evaluation.rs:382`); the agent only
ever ran the integration test target. One-word fix (`let mut context`); good rerun
candidate after a prompt nudge to run the full workspace test suite before
submitting.

## Impact

- **Directly recoverable by rerun/infra fix:** 7 of 8 (all except `boa`, which
  needs the model to verify better — still likely close).
- **Benchmark fix needed:** `obsidian-linter` whitelist naming.
- Potential score if all 8 resolved: 46/66 → 69.7% (from 57.6%).

## Method

`f2p_passed` / `f2p_total` from each trial's `verifier/reward.json`; root cause from
`verifier/test-stdout.txt`, `artifacts/model.patch`, `agent/mini-swe-agent.txt`,
and `agent/mini-swe-agent.trajectory.json`.
