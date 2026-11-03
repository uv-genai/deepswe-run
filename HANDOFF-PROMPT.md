# Session-restart prompt

You are resuming work on the DeepSWE benchmark project. Follow these instructions.

**Start:** `cd /home/ugo/projects/deepswe-test` — everything below is relative to it.

**Read first, completely:** `HANDOFF.md`. It is the live single source of truth —
current standing, environment map, hard-won rules, pending work, preflight
checklist, cheat sheet. Dated `HANDOFF-*.md` files are frozen history; ignore
them unless you need detail they alone contain. `README.md` has full setup and
troubleshooting docs; `reports/` holds the results of record.

**Then, in order:**

1. Run the §8 preflight checklist from `HANDOFF.md` exactly as written and
   report the results (all green, or which check failed) before anything else.
2. Summarize §6 (pending work) and ask the operator which item to start.
   **Do not launch benchmarks or change configuration on your own** — the
   operator launches long jobs themselves; you prepare, verify and watch.

**Non-negotiable boundaries:**

- **Only this directory.** Never touch other projects, services, or system config
  outside what `HANDOFF.md` explicitly documents as this project's.
- **`litellm.service`, model backends, and pier's site-packages are the
  operator's domain.** File edits only on explicit operator request; never
  start/stop/restart a service unless the operator explicitly tells you to in
  that moment. The two pier patches (`reapply-litellm-pin.sh`,
  `reapply-squid-timeout.sh`) are restored only when asked.
- **No model probes or warm-up requests unless asked** — they show on the
  operator's dashboards. Launch scripts' built-in preflights are fine.
- **Safe kills only:** the exact `pkill -f` pattern from `HANDOFF.md` §3, with
  `-9` (SIGTERM is ignored); never a broad pattern. Reclaim leaked trial
  networks after any kill.
- Results are graded and kept under `jobs/` — never delete or overwrite an
  existing job dir; the launchers refuse to, and so should you.

**Working practice:**

- After any state change (results, config, completed pending item), update
  `HANDOFF.md` **in the same commit** — it must stay accurate for the next
  session. Keep report matrices (`reports/final-report-*.md`,
  `reports/maya-campaign-*.md`) filled in as batches land.
- Commit messages document each change and incident (established practice);
  commit as work lands, push when the operator asks.
- When reviewing benchmark results: classify failures before judging the model
  (context wall, format abort / empty patch, squid or litellm timeout, verifier
  artifact vs genuine capability) — `HANDOFF.md` §3 and the final report §3
  explain every known class.
- Be concise; surface assumptions; ask rather than guess when a decision is the
  operator's.
