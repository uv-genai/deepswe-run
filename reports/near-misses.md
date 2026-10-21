# DeepSWE Near-Miss Report

**Job:** `jobs/deepswe-gufo-qwen3.8-flash-next-tp2-q8`
**Model:** `openai/gufo-qwen3.8-flash-next-tp2-q8`
**Graded:** 61 trials — 35 solved (57.4%) — 12 near misses (fail-to-pass diff == 1)

See also: `zero-pass.md` for the 7 trials with `f2p_passed == 0`.

Near miss = the agent passed all but **one** fail-to-pass test (`f2p_total - f2p_passed == 1`).
All 12 are scored `reward: 0` despite partial credit ≥ 0.957 — binary scoring gives no
credit for near-complete solutions.

**If all 12 were solved, the score would go from 35/61 (57.4%) to 47/61 (77.0%).**

## Near misses (12)

| # | Task | f2p | Partial | The one failing test |
|---|------|-----|---------|----------------------|
| 1 | awilix-async-container-initializ__WZzi2xc | 23/24 | 0.995 | `allows scope.initialize() without calling parent.initialize() first` |
| 2 | bandit-interprocedural-taint-che__B3CQu4V | 65/66 | 0.997 | `test_non_spec_sanitizers_do_not_break_taint` |
| 3 | clack-async-autocomplete-options__kXvCVmN | 81/82 | 0.999 | `previous AbortController is aborted when new fetch starts` |
| 4 | dynamodb-toolbox-conditional-att__CRcGwMd | 30/31 | 0.999 | `chaining multiple requiredIf calls uses OR semantics` |
| 5 | fastapi-implicit-head-options__8Ti6Fp6 | 42/43 | 1.000 | `test_options_payload_excludes_head_operation_and_reports_explicit_head_in_methods` |
| 6 | happy-dom-deterministic-intersec__ToLKtXU | 13/14 | 0.957 | `Detects threshold crossings in subsequent async delivery cycles` |
| 7 | httpx-multipart-response-parsing__xYQuAn8 | 121/122 | 0.999 | `test_iter_multipart_part_headers_parsing[X: 1\r\n\tz...]` (folded-header edge case) |
| 8 | httpx-streaming-json-iteration__z4fCCG5 | 107/108 | 0.999 | `test_iter_json_ndjson_invalid_line_raises_and_closes_streaming_response` |
| 9 | ink-grid-box-layout__yKUZqyD | 24/25 | 0.986 | `minmax with fr max distributes remaining space` |
| 10 | kea-atomic-signal-selectors__kugbKgo | 11/12 | 0.993 | `hybrid engine can be enabled and disabled` |
| 11 | koota-deferred-mutation-buffer__GC9JNX4 | 70/71 | 0.995 | `Deferred Wildcard Relation Removal > should fire onRemove for each removed pair` |
| 12 | koota-pair-relation-tracking__c3vDawX | 37/38 | 0.995 | `Pair-level and trait-level coexistence > should require both when used together in AND` |

## Notable patterns

- Several misses are **single edge cases** of an otherwise complete implementation:
  folded multipart headers (`httpx-multipart`, 121/122), ndjson error handling
  (`httpx-streaming-json`, 107/108), nested scope initialization (`awilix`, 23/24),
  AbortController lifecycle (`clack`, 81/82), `minmax`+`fr` layout math (`ink`, 24/25).
- `fastapi-implicit-head-options` has partial credit **1.0** — the agent's solution is
  functionally complete, but one f2p test still fails (likely a reporting/edge detail).
- `kea-atomic-signal-selectors` at 11/12 suggests a missing toggle for the hybrid engine
  rather than a logic bug.

## Honorable mention (fail == 2)

| Task | f2p | Partial |
|------|-----|---------|
| effect-sse-httpapi-streaming__spmA3ez | 45/47 | 0.983 |

## Method

`f2p_passed` / `f2p_total` read from each trial's `verifier/reward.json`;
failing test names extracted from `verifier/test-stdout.txt` grade sections.
Regenerate with: scoreboard data over `jobs/deepswe-gufo-qwen3.8-flash-next-tp2-q8/*/verifier/reward.json`.
