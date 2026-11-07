# Model comparison — what each arm is good at (gufo Q8 vs GLM-5.3 vs DeepSeek v4.1 Flash)

**Date:** 2026-11-04 · **Evidence base:** gufo full campaign (113 tasks / 186 trials,
`final-report-2026-10-26.md`) + maya-campaign single-task datapoints (`maya-campaign-2026-10-31.md`)
**Models:** `gufo-qwen3.8-flash-next-tp2-q8` · `maya-glm5-{s,m,l}-tp2-mtp` (GLM-5.3 quants)
· `maya-deepseek-{xs,s}-dspark` (DeepSeek v4.1 Flash @ Q1 / Q2/3, [mw00/project-maya](https://github.com/mw00/project-maya))
**Caveat up front:** only gufo has corpus-scale evidence. Every other arm has **1–2 tasks** —
profiles below are hypotheses to be confirmed by the `failed23` batches, not rankings.

---

## 1. The evidence

| | wasmi (gufo: failed 6×, **solved on attempt 7**, 2026-11-07) | awilix (gufo: 0 in 2 attempts) |
|---|---|---|
| gufo Q8 | ✅ **22/22** (post-upgrade; earlier: 3× wall, rabbit-hole, Sync-breaking 20/22) | 23/24 ×2 (identical edge test) |
| **GLM-5.3 S / M / L** | ✅ **22/22 — all three** | S: not run · M: 23/24 · L: 23/24 |
| **DeepSeek v4.1 Q2/3** | not run | ✅ **24/24 — only solve** |
| DeepSeek v4.1 Q1 | not run | 23/24 (same edge test) |
| **gufo Q4 (same weights as Q8)** | ✅ **22/22** (attempt 1, 11-07) | 23/24 (same edge test) |

**Nobody holds both tasks.** gufo recovered **wasmi** itself on attempt 7; **awilix**
remains unsolved by gufo. Among the maya arms the tasks went to different families
(GLM took wasmi, DeepSeek took awilix). All non-gufo results are first attempts.

Full run detail (7 non-gufo runs + gufo's wasmi retest, all clean post-2026-11-03):

| Arm | Task | reward | f2p | p2p | Effort |
|---|---|---|---|---|---|
| deepseek-s (Q2/3) | awilix | **1** | 24/24 | 162/162 | 54 min, 74 steps, 83.6 k out |
| deepseek-xs (Q1) | awilix | 0 | 23/24 | 162/162 | 51 min, 55 steps, 62.4 k out |
| glm5-m | awilix | 0 | 23/24 | 162/162 | 46 min, 80 steps, 62.5 k out |
| glm5-l | awilix | 0 | 23/24 | 162/162 | 61 min, 74 steps, 77.7 k out |
| glm5-s / m / l | wasmi | **1** | 22/22 | 58/58 | S: 163 min/186 k out · M: 81 min/93 k · L: 100 min/94 k |
| gufo q8 (post-upgrade) | wasmi | 0 (attempt 6) | 20/22 | **0/58** | 99 min, 292 steps — patch broke `Store: Sync` (E0277) |
| **gufo q8 (post-upgrade)** | **wasmi** | **1 (attempt 7)** | **22/22** | **58/58** | 67 min, 182 steps, 83 KB, 164 k out |
| gufo q4 | wasmi | **1** | 22/22 | 58/58 | 69 min, 250 steps, 79 KB, 203.6 k out |
| gufo q4 | awilix | 0 | 23/24 | 162/162 | 45 min, 114 steps, 89 KB, 123.4 k out |

### 1.1 Effort comparison — wasmi: five runs, one identical score

The cleanest cross-model efficiency evidence available: same task, same
commit-mandate config, all five **22/22 with green p2p** (gufo Q8 vs Q4 is the
**same-weights A/B** — only the bit depth differs).

| Metric | gufo Q8 (att. 7) | **gufo Q4** | GLM-5.3 M | GLM-5.3 L | GLM-5.3 S (2-bit) |
|---|---|---|---|---|---|
| Wall time | **67 min** 🥇 | 69 min | 81 min | 100 min | **163 min** |
| Steps | **182** | 250 | 195 | 227 | **308** |
| sec/step | 22 | **17** 🥇 | 25 | 26 | 32 |
| Input tokens | 39.3 M | 53.0 M | **24.7 M** 🥇 | 28.7 M | 73.5 M |
| in/step | 216 k | 211 k | 127 k | 126 k | 239 k |
| Output tokens | 164.4 k | 203.6 k | **92.8 k** 🥇 | 94.4 k | 185.9 k |
| out/step | 903 | 814 | 476 | 416 | 603 |
| Cache hit | 99.5 % | 99.6 % | 99.2 % | 99.3 % | 99.5 % |
| Patch | 83 KB | 79 KB | 71 KB | 68 KB | 98 KB |

1. **Speed ranking: gufo ≈ Q4 < M < L ≪ S.** gufo Q8 wins on *steps*, not tokens: its
   responses are ~2× longer per step (903 vs M's 476) but it takes fewer, faster
   steps and never stalls. Q4 shows the other side of the same coin: **+37 % steps
   for the same score, offset by 23 % faster decode** (17 s/step — smallest weights
   win the memory-bound loop). Wall time = steps × sec/step, so S's 2.4× penalty
   comes from **both** factors (308 steps × 32 s).
2. **Context discipline differs sharply:** gufo re-sends a ~200 k-token working
   context each step (216 k in/step) vs GLM's ~126 k — more history carried, but
   the prefix cache absorbs it (99.5 % hit either way). **GLM-M is the most frugal
   overall: 24.7 M input / 92.8 k output ≈ ⅓ of gufo's input and ½ its output** for
   the identical result.
3. **S repeats the awilix tax:** 3.0× M's input, 2.0× its output, 2.4× the wall
   time for the same score — at 2-bit the cost is purely efficiency.
4. **Patch sizes converge (68–98 KB)** — implementation size separates no one.
5. **gufo's solve was not an outlier effort:** its wasmi band across all attempts
   is 57–85 min / 147–214 steps; attempt 7 (67 min / 182 steps) is mid-band. The
   earlier zeros were wall/behavior failures, not under-effort.
6. **DeepSeek has not run wasmi** (no job exists) — the remaining datapoint: it
   would be the only maya arm holding both tasks, and its efficiency profile on
   this task is unknown.

## 2. Per-model profiles

| Model | Strength | Weakness | Evidence |
|---|---|---|---|
| **gufo Qwen3.8 Q8** | **Breadth** — the only corpus-proven model (**91/113 = 80.5 %** after the 11-07 wasmi solve); strong on long-horizon work across 5 languages; its residuals are almost all 1–2-test edges (17/23 at partial ≥ 0.95) | **Deterministic behavioral misses**: breaks existing tests (3 chronic p2p regressors — *same test every attempt*), misses precise edges (awilix, kea — *same test 4×*), rabbit-holes on huge specs (wasmi — *recovered on attempt 7*), submission fragility (fixed by commit-mandate), and on attempt 6 **broke the `Store: Sync` invariant** → p2p 0/58 | 113 tasks, 187 trials |
| **GLM-5.3 M** | **Complex feature implementation under strict invariants** — first-try 22/22 on the task gufo never solved; never broke p2p in any run; **best efficiency of the three sizes** (46–81 min, 62–93 k out) | misses the gufo-identical edge tests (awilix 23/24) | 2 tasks |
| **GLM-5.3 L** | results identical to M (22/22, 23/24) at near-identical cost (+1.7 % output, +16 % steps, +23 % time) | **thinks much longer per response** (one 792 s request killed it under the old 600 s timeout) → latency pressure; **no accuracy premium over M observed** | 2 tasks |
| **GLM-5.3 S (2-bit)** | solves everything M solves (wasmi 22/22) | **worst efficiency: 2× output, 3× input, 1.6× steps, 2× wall time** vs M for identical outcomes | 1 task |
| **DeepSeek v4.1 Q2/3** | **the edge-finder** — only arm to solve awilix when five arms were stuck on the identical test, first try | n = 1; spent 34 % more output than GLM-M for its solve | 1 task |
| **DeepSeek v4.1 Q1** | remarkably bit-robust: 23/24 — one test behind its own Q2/3 sibling, level with Qwen **Q8** | lost the edge at the extreme low end | 1 task |

## 3. Quantization vs model size

1. **Bits buy cost, not capability — until the very bottom, and now controlled:**
   gufo **Q8 vs Q4 (identical weights)** produced *identical outcomes* on both tasks
   (wasmi solved by both, awilix missed by the same single test) — Q4 paid +37 %
   steps / +24 % output on wasmi but **decoded 23 % faster** (17 vs 22 s/step), so
   wall time stayed within 3 %. Cost moves in *tokens*, not clock time. Across
   families: GLM S(2-bit) matched M at ~2× the tokens; DeepSeek Q1 lost exactly one
   test vs Q2/3 — the *efficiency* tax is continuous, the *correctness* tax only
   becomes visible at Q1.
2. **Size bought nothing measurable here:** GLM L ≡ GLM M in results and near-identical
   in cost; L's only real difference is thinking length — a latency issue, now
   absorbed by the raised timeouts.
3. **Family/behavior dominates bit depth:** the **highest-bit model in the comparison
   (Qwen Q8) lost both tasks** to lower-bit rivals. gufo's failures are behavioral
   (regression-proneness, edge engagement, rabbit-holing), not precision — which is
   also why additional bits never helped it.
4. **Correction to the intuitive reading:** DeepSeek Q2/3 is 1-for-1, not yet "the most
   capable" — GLM has solved wasmi three ways. Sample sizes are 1–2 tasks per arm.

## 4. Which model for which task

| Task type | Pick | Why |
|---|---|---|
| Broad corpus runs, leaderboard one-shot, anything needing the most evidence | **gufo Q8** | only model validated at 113-task scale |
| Long-horizon feature work where build/tests must stay green | **GLM-5.3 M** (L if you want more thinking — headroom now exists) | solved wasmi first try, never broke p2p |
| Tasks where everyone clusters at one failing edge test | **DeepSeek v4.1 Q2/3** | only arm to break the awilix logjam |
| GLM S | avoid unless memory-bound | same outcomes as M at 2–3× cost |
| **The remaining 23** | run `failed23` on **GLM-M** and **DeepSeek-S**, take per-task best | turns 2 tasks of evidence into 23 |

## 5. Evidence gaps → next runs

- **DeepSeek on wasmi** — if it lands 22/22, DeepSeek becomes the only *maya arm*
  holding **both** tasks (gufo has wasmi now; awilix is the open one for everyone else)
- **GLM-S on awilix** — completes the 2×2 and the quant ladder on the edge task
- **`failed23` arms** (`MODEL=<id> ./scripts/rerun-subset.sh failed23 --incremental -n 2`)
  for GLM-M and DeepSeek-S — the only way these profiles become rankings; fill the
  matrix in `maya-campaign-2026-10-31.md`
- **Done:** the gufo **Q8-vs-Q4 same-weights control** (wasmi + awilix, 2026-11-07) —
  identical outcomes both tasks; see §1.1 and §3

## Source reports

`final-report-2026-10-26.md` (gufo campaign, failure taxonomy) ·
`maya-campaign-2026-10-31.md` (per-task matrix, Datapoints 1–2) ·
`quant-sensitive-tasks.md` (scorecard plan, Q8-vs-Q4 control arm)
