# Zero-Pass Analysis Summary

**Job:** `jobs/deepswe-gufo-qwen3.8-flash-next-tp2-q8`
**Model:** `openai/gufo-qwen3.8-flash-next-tp2-q8`
**Date:** 2026-10-19

All 8 zero-pass trials analyzed (per-task details in `analysis-<task>.md`).
**6 distinct failure modes** across the 8 tasks:

| Task | f2p | Root cause |
|---|---|---|
| arktype-json-schema-refs-depende | 0/25 | `RepeatedFormatError` — 5× output-token-limit, never committed |
| boa-hierarchical-evaluation-canc | 0/17 | Real 78KB patch, but it **breaks Rust lib-test compilation** (E0596 — `context` not `mut`); agent only ever ran the integration test target |
| dynamodb-toolbox-lazy-recursive | 0/37 | `context_length_exceeded` (262k) after 162 calls, 0 commits — work lost |
| kcp-go-multiplexed-kcp-streams | 0/30 | **Infra**: squid proxy read timeouts against the LLM endpoint after only 6 API calls (`--exit-immediately`) |
| kombu-virtual-queue-dead-letteri | 0/76 | **Model hallucination** — model chased a different task entirely ("syntax error in `cplit.py`" in `/home/parker/projects/workspace`), 19 unparseable outputs, 18 calls |
| koota-composite-trait-aspects | 0/51 | `context_length_exceeded` after 152 calls; branch `feat/aspects` with real edits but 0 commits |
| koota-query-predicates | 0/43 | `RepeatedFormatError` (3× output-token-limit), 0 commits |
| obsidian-linter-auto-table-of-co | 0/41 | **Verifier bug** — jest actually passed **38/41** f2p, but whitelist names ("Auto Table of Contents…") don't match CTRF names ("Table of Contents Generator…") → all 41 "missing from report" |

## Key takeaways

1. **Only 1 of 8 is a genuine solution failure** (boa — and it's a one-word fix:
   `let mut context`).
2. **4 died to context/output limits** (arktype, dynamodb-toolbox, koota-composite,
   koota-query) with zero commits — real implementation work was thrown away.
   Enabling context compaction and/or raising `max_output_tokens` would likely
   convert several.
3. **obsidian-linter is a benchmark bug** — no agent can pass it as scored; flagged
   for fixing on the verifier side. (It also has 3 genuine small bugs: `{#id}` /
   trailing `#` not stripped from TOC link text — true f2p would be 38/41.)
4. **kcp-go is a pure infra rerun** — check squid/vLLM health around
   2026-10-18 ~16:53 UTC.
5. **kombu looks like a one-off model malfunction** — rerun; investigate if the
   off-task hallucination recurs.
6. Resolving all 8 would move the score from **38/66 (57.6%) to ~46/66 (69.7%)**.

## Cross-cutting finding

In 3 trials (boa, kombu, obsidian-linter) the final
`echo COMPLETE_TASK_AND_SUBMIT_FINAL_OUTPUT` was reported as
**"action was not executed"** — a mini-swe-agent format-parsing quirk. It didn't
matter where commits existed (boa, obsidian — patch recovered via
`git diff base..HEAD`), but it killed kombu outright. Worth tracking in the
harness.

## Files in this folder

- `zero-pass.md` — zero-pass overview with category breakdown
- `near-misses.md` — 12 trials failing by exactly one f2p test
- `analysis-<task>.md` — one deep-dive per zero-pass trial (8 files)
