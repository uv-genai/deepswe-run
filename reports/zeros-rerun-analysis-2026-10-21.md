# DeepSWE — Zero-Success Rerun: Per-Task Failure Analysis

**Job:** `jobs/deepswe-gufo-qwen3.8-flash-next-tp2-q8-zeros-rerun`
**Model:** `gufo-qwen3.8-flash-next-tp2-q8` (via `openai/…` at the local LiteLLM proxy)
**Runner:** Pier + mini-swe-agent 2.4.6 (litellm pinned to 1.105.1), `--n-concurrent 1`
**Task set:** the 16 hard-zero tasks (reward 0, f2p < 50%) from the completed 113-task main job
**Analysis date:** 2026-10-21
**Method:** per-trial `verifier/reward.json`, `verifier/ctrf.json` (test-level failures), `artifacts/model.patch` (size + files touched), and full `agent/mini-swe-agent.txt` transcripts (edit/commit/context-wall markers, termination cause)

---

## Outcome

| | |
|---|---|
| Tasks run | 16 |
| **Solved** | **3** — `boa-hierarchical-evaluation-cancellation` (17/17), `kcp-go-multiplexed-kcp-streams` (30/30), `obsidian-linter-auto-table-of-contents` (41/41) |
| Zero | 13 |
| Errored / unfinished | 0 |

Three tasks that the main run scored 0 on were solved outright on a fresh attempt
(pass@2 recovery). The remaining 13 zeros fall into five distinct failure classes —
**only 4 of the 13 are genuine "model couldn't do it" outcomes**.

---

## A. Worked, never submitted — 7 tasks (the dominant failure mode)

DeepSWE's collect hook captures **committed work only**:
`git diff --binary <base_commit> HEAD`. These agents did substantial work —
12–72 edit operations, the feature branch created as instructed, repo test suites
executed — but the run terminated **before the final commit**, so the captured patch
was 0 bytes and the verifier graded the untouched base repository. Every f2p test
fails on the base repo by construction, so these are zeros *regardless of the work
produced*.

| Task | Evidence of real work | Termination |
|---|---|---|
| `koota-composite-trait-aspects` | 24 edit ops; diffstat incl. `world.ts +21` | `RepeatedFormatError`; last act `git checkout HEAD -- trait.ts` |
| `koota-query-predicates` | 26 edits; `queries.md +25` | `RepeatedFormatError`; ended inspecting `git diff --stat` |
| `opa-template-string-reconstruction` | 28 edits; branch `fix/partial-template-string` | `RepeatedFormatError`; last act `git status --short` |
| `python-statemachine-state-data-scoping` | 11 edits; `statemachine.py +110` | `RepeatedFormatError`; ended on `git diff --stat` |
| `scriggo-method-declarations` | **61 edit ops**; `test/misc/program_test.go +95` | `RepeatedFormatError` |
| `valibot-recursive-schema-composition` | **72 edit ops**; branch `feat/recursive-schema` | `RepeatedFormatError` |
| `oxvg-structural-selector-preservation` | 17 edits | Died **mid-commit** — last commands literally `git add`, `git commit -a` (also hit the context wall, see B) |

`RepeatedFormatError` is mini-swe-agent's harness abort after the model repeatedly
emits output that fails its format check — most plausibly while trying to produce
the final commit/submit action. No command executes after it. Net effect:

> **7 tasks lost to the submission pipeline, not to model capability.**
> `scriggo` shipped +95 lines of test-code work that scored 0 because it lived in an
> uncommitted working tree.

## B. Context starvation — 3 tasks (ceiling-limited, deterministic)

- `dynamodb-toolbox-lazy-recursive-schemas` (failed **both** runs identically)
- `wasmi-trap-coredumps`
- `oxvg-structural-selector-preservation` (also in class A)

Conversations exceeded the backend's **262,144-token context**; every subsequent
call returns a permanent `400 context_length_exceeded` ("prompt exceeds the
262144-token context"), retried ~12× futilely. dynamodb's final act was
`git log --oneline -5 && git status` — reviewing completed work as the wall killed it.

**Re-running unchanged will reproduce these results.** Requires either a larger
`--context` on the serving side or an agent with history truncation (mini-swe has none).

## C. Deliberate empty submission — 1 task

- `kombu-virtual-queue-dead-lettering`

The model investigated, found *"no jigsaw/puzzle code in tree or history"*, and
**chose** to submit an empty diff, arguing *"a correctly empty diff"* beats risky
changes. Defensible engineering judgment; a benchmark zero. (Its lone exception-free
1,216-line transcript is the shortest in the batch.)

## D. Genuine near-misses — one failing test each (pass@2 candidates)

| Task | Score | The single failing test | Why |
|---|---|---|---|
| `pwntools-tube-multiplexing` | **72/73** | `test_concurrent_open_close` — `EOFError: remote refused to open channel 1` under concurrent open/close | Thread-race edge in the implementation; **the agent never ran this specific test** (0 mentions in transcript) |
| `termenv-preserve-ansi-resets` | **34/35** | `TestTruncate_DoesNotSplitOSCSequence_WhenWidthZero` — want OSC-8 hyperlink preserved, got `""` | Width-0 truncation edge case; **also never ran this test** |

## E. Partial implementation — 1 task

- `igel-persist-feature-schema` — **6/24 f2p**. Feature-schema validation/aliasing
  works; the **persistence layer is missing**: all 18 failures are
  `FileNotFoundError: model.joblib / description.json (under model_results/)`.
  `fit`/`evaluate`/`export` never write the required artifacts to disk.

---

## Recommendations

1. **Fix submission robustness first** — it alone accounts for 7/13 zeros. Options:
   - instruct/commit incrementally ("commit after each working feature" instead of
     once at the end) — e.g. via a mini-swe prompt-template override;
   - or extend collection to fall back to the working tree when `git diff base HEAD`
     is empty (task-harness change; must be applied uniformly to stay comparable).
2. **Context ceiling:** raise the backend's `--context` above 262k or accept that
   context-hungry tasks (dynamodb, wasmi) are ceiling-limited for this agent.
3. **The two 1-test misses** are the highest-value re-runs — the required behavior is
   demonstrably within the model's reach.
4. `kombu` and `igel` are genuine model/judgment misses; re-runs are fair but
   lower-probability.

## Context: overall corpus standing (unique tasks, single-attempt-per-clean-run)

- Main job: 66/113 solved (+ arktype via standalone run = **67**)
- Zeros rerun: +3 (**boa, kcp-go, obsidian-linter-toc**) → **69/113 (61.1%)**
- Remaining unsolved: 13 in this report + 30 near-miss tasks (separate batch)
