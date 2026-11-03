 1. Already visible in the wasmi data: efficiency at equal score

 S (2-bit) and M/L solved identically, but S burned 2× output, 3× input, 1.6× steps, +36% patch size for the same 22/22. That's the classic signature — quantization loss doesn't necessarily flip the reward, it inflates the cost of getting
 there. So build a scorecard from failed23:

 ┌────────────────────────────────────────┬─────────────────────────────────────────────────────────────────────────────────────────────────────┐
 │ Metric                                 │ Why it's quant-sensitive                                                                            │
 ├────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────┤
 │ solves (reward=1)                      │ coarsest signal                                                                                     │
 ├────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────┤
 │ output tokens / solved, steps / solved │ the S-vs-M gap above, averaged over 23 tasks                                                        │
 ├────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────┤
 │ mean partial                           │ graded — a low-bit model that can't quite land edge cases drags partial down even when a task flips │
 ├────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────┤
 │ p2p failures                           │ collateral damage — weaker models touch unrelated code; gufo Q8 gave 0 p2p fails on 22/22           │
 ├────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────┤
 │ patch size / steps                     │ surgical vs flailing (wasmi: 98 KB vs 68–71 KB)                                                     │
 └────────────────────────────────────────┴─────────────────────────────────────────────────────────────────────────────────────────────────────┘

 2. The controlled arm you're missing: same weights, different bits

 gufo-qwen3.8-flash-next-tp2-q4 is already served by the proxy (saw it in /v1/models). Running the same failed23 batch on Q8 vs Q4 of the identical model isolates quantization from architecture — your S-vs-gufo comparison currently
 confounds bits with model family:

 ```bash
   MODEL=gufo-qwen3.8-flash-next-tp2-q4 ./scripts/rerun-subset.sh failed23 --incremental -n 2
 ```

 (guard selects all 23 — that model has solved none; job …-tp2-q4-failed23-rerun-inc)

 3. The precision probe: the 6 deterministic near-miss tasks

 kea (hybrid-engine toggle), httpx-streaming (ndjson line), awilix, mashumaro, obsidian-link, prometheus all failed the same single test across every gufo attempt — they're one-precise-edge tasks, exactly where bit-depth bites. Run each
 quant on them k times and compare flip rates: if S flips a task that M solves3/3, that's quant sensitivity with error bars. (Also cheap: the harness already records RepeatedFormatError/empty-patch/submit-quirk rates — malformed tool
 calls rise with quant pressure, and gufo Q8's baseline rates are in the final report.)

 4. What not to use

 gql/bandit/pest (chronic p2p regressors) are model-behavior quirks — gufo-specific, not bit-related; and kombu is a judgment call. Exclude them from any quant score or they'll add noise.

 ────────────────────────────────────────────────────────────────────────────────

 Suggested setup: a small quant section in reports/maya-campaign-2026-10-31.md (or a sibling reports/quant-validation-*.md) with the scorecard columns pre-built for {GLM-5.3 2-bit, GLM-5.3 mid, GLM-5.3 high, Qwen Q4, Qwen Q8}. Want me to
 create it, and add gufo-…-q4 as a ready arm? And since you mentioned a platform upgrade — I still need one line on what changed so the post-upgrade gufo numbers get their own phase note rather than being merged with the 90/113 campaign.
