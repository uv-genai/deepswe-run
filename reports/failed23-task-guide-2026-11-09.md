# The 23-task residual set — what each task is and how complex it is

**Date:** 2026-11-09 · **Source:** each task's own metadata in `deep-swe/tasks/<slug>/`
(`task.toml` → title/description/language/repo, `instruction.md` → full prompt,
`solution/solution.patch` → reference solution, `tests/test.patch` → added tests)
**Context:** the `failed23` group (`scripts/rerun-subset.sh`) — the 23 tasks unsolved by
gufo at the final-report cut. Companion: `final-report-2026-10-26.md` §3.

**Standing note:** gufo has since solved 3 more in its own `failed23` arm
(fastapi-deprecation, fastapi-implicit, pebble) → **gufo = 94/113 (83.2 %), residual 19**.
Across *all* arms, **11 of the 23 are now solved by at least one model**; 12 remain open
for everyone. All 23 are `category = feature_request` — DeepSWE tasks are written from
scratch as features, never adapted from real commits (contamination-free by design).

## How the complexity tiers were derived

Three **intrinsic** factors (model-independent — a task's difficulty for *any* agent),
each scored 0–3, summed to a 0–9 tier:

| Factor | 0 pts | 1 pt | 2 pts | 3 pts |
|---|---|---|---|---|
| Reference-solution size (added lines) | < 500 | 500–650 | 650–850 | > 850 |
| Spec length (`instruction.md`) | < 1.5 KB | 1.5–2.5 KB | 2.5–3.5 KB | > 3.5 KB |
| Verification breadth (f2p tests) | < 25 | 25–60 | 60–120 | > 120 |

**Tiers:** 0–2 simple · 3–5 medium · 6–7 hard · 8–9 very hard → distribution: **6 simple, 15 medium, 2 hard, 0 very hard**.

> **Read the tier as structural size, not observed difficulty.** Every reference solution
> here is 470–1030 added lines — there are no toy tasks; even "simple" means a
> several-hundred-line feature. *Observed* difficulty (how hard our models actually found
> it) is the **attempts** and **status** columns plus the notes — e.g. awilix is structurally
> "simple" but took **10 attempts across 5 arms with only one solve** because it hinges on
> a single edge case.

## The table (sorted by tier)

| Tier | Task | Lang / Repo | What it asks for | Spec | Ref-sol | f2p | Atts | Status / note |
|---|---|---|---|---|---|---|---|---|
| **hard** | `fastapi-deprecation-response-headers` | python / fastapi | Deprecation, Sunset + successor `Link` headers, OpenAPI metadata, tracking middleware for deprecated routes | 3.1 k | 784 ln | 137 | 4 | ✅ gufo + glm — the largest test suite of the set |
| **hard** | `kombu-virtual-queue-dead-lettering` | python / kombu | Dead-letter routing, TTL expiry, max-length overflow for the virtual transport layer | 4.5 k | 627 ln | 76 | 5 | ✅ glm — longest spec; one gufo attempt *deliberately submitted an empty diff* |
| medium | `bandit-structured-nosec-directives` | python / bandit | Region + next-line `nosec` directives with selector expressions, ignore-nosec handling | 2.8 k | 629 ln | 69 | 4 | ⚠️ **p2p-regressor**: breaks the *same* existing test every attempt |
| medium | `csstree-shorthand-expansion-compression` | javascript / csstree | Lexer methods expanding CSS shorthands↔longhands | 2.9 k | 518 ln | 79 | 4 | open — best 76/79 |
| medium | `fastapi-implicit-head-options` | python / fastapi | Implicit HEAD + automatic OPTIONS across routers/includes | 1.7 k | 939 ln | 43 | 3 | ✅ gufo (largest reference solution of the set) |
| medium | `httpx-multipart-response-parsing` | python / httpx | Response iterators parsing multipart bodies into parts | 2.2 k | 600 ln | 122 | 3 | open — best 121/122 (one folded-header edge) |
| medium | `httpx-streaming-json-iteration` | python / httpx | Response iterators incrementally parsing streaming JSON | 2.6 k | 523 ln | 108 | 3 | open — same single ndjson edge test every attempt |
| medium | `koota-deferred-mutation-buffer` | typescript / koota | Deferred command buffer batching entity mutations during query iteration | 1.0 k | 1031 ln | 71 | 4 | open — biggest reference solution; best 70/71 |
| medium | `pebble-durability-wait-apis` | go / pebble | Durability callbacks, wait methods, notifications, metrics for sync writes | 2.8 k | 654 ln | 59 | 4 | ✅ gufo + glm |
| medium | `updo-policy-alerting` | go / updo | Policy-driven alerting: consecutive failures, latency, recovery, SSL expiry | 4.6 k | 669 ln | 17 | 4 | ✅ glm — second-longest spec |
| medium | `effect-sse-httpapi-streaming` | typescript / effect | Typed SSE streaming endpoints, codecs, client handling for HttpApi | 2.3 k | 829 ln | 47 | 4 | open — best 46/47 |
| medium | `kea-atomic-signal-selectors` | typescript / kea | Atomic selector tracking with dependency health, circular detection, unchanged lifecycle | 3.5 k | 669 ln | 12 | 6 | ✅ glm — *same single f2p test failed in every gufo attempt* |
| medium | `obsidian-linter-link-format-conversion` | typescript / obsidian-linter | Link Style rule: wiki↔markdown link/image conversion preserving ignored regions | 2.2 k | 769 ln | 60 | 4 | open — best 59/60 (3 escaped-label edges) |
| medium | `prometheus-transactional-reload-status` | typescript / prometheus | Opt-in transactional config reload: durable outcomes, rollback, HTTP status endpoint | 1.9 k | 973 ln | 15 | 4 | ✅ glm (via commit-mandate after a loop-timeout trial!) |
| medium | `mashumaro-flattened-dataclass-fields` | python / mashumaro | `field_options` flattening nested dataclasses with prefix/rename validation | 0.6 k | 523 ln | 66 | 4 | ✅ glm — shortest spec of the set; best 63/66 (3 alias cases) |
| medium | `termenv-preserve-ansi-resets` | go / termenv | ANSI tokenization, reset-preserving truncation, style-aware output | 1.7 k | 512 ln | 35 | 6 | open — best 34/35 (width-0 OSC edge) |
| medium | `wasmi-trap-coredumps` | rust / wasmi | Opt-in Wasm coredumps on traps: strict binary format, LEB128, four custom sections, re-entrant frame capture | 3.2 k | 596 ln | 22 | 10 | ✅ gufo-q8/q4 + glm s/m/l — hardest-won: 3× context wall, 1 rabbit-hole, 1 Sync-breaking near-miss |
| simple | `awilix-async-container-initialization` | typescript / awilix | Dependency-aware async initialization: ordered startup, concurrency limits, rollback | 2.3 k | 557 ln | 24 | 10 | ✅ deepseek-Q2/3 only — structurally small but a **single edge case** blocked 9 other attempts |
| simple | `gql-incremental-graphql-delivery` | python / gql | `@defer`/`@stream` incremental delivery across HTTP multipart, WebSocket and the DSL | 1.6 k | 537 ln | 17 | 6 | ⚠️ **p2p-regressor** — f2p perfect 4/4 attempts, same existing test broken 4/4 |
| simple | `koota-pair-relation-tracking` | typescript / koota | Tracking modifiers distinguishing specific relation pairs vs trait-level changes | 1.1 k | 547 ln | 38 | 4 | ✅ glm — was once wiped to 0/38 by a format-abort (harness casualty) |
| simple | `meriyah-explicit-resource-declarations` | typescript / meriyah | Parser + AST for `using`/`await using` with context-sensitive errors | 1.4 k | 573 ln | 49 | 4 | open — once wiped to 0/49 by the same format abort; best 48/49 |
| simple | `pest-character-class-coalescing` | rust / pest | Optimizer passes collapsing choice chains into character classes | 1.2 k | 471 ln | 104 | 4 | ⚠️ **p2p-regressor**: main run had perfect f2p + broken p2p; rerun inverted |
| simple | `ink-grid-box-layout` | typescript / ink | CSS Grid parsing/placement in the Box component: tracks, gaps, positioning | 0.9 k | 479 ln | 25 | 6 | open — was a context-wall victim (0/25); best 24/25 |

## Observed-difficulty patterns (independent of the tiers)

- **Chronic p2p regressors (3):** `gql`, `bandit`, `pest` — never *solved*, but the failure
  is always collateral damage to an existing test, often the same one every attempt.
- **Single-edge walls:** `awilix`, `kea`, `httpx-streaming`, `termenv`, `csstree`,
  `obsidian-link`, `httpx-multipart` — models reach 95–99 % and stop on one precise case;
  several fail the *identical* test across models and attempts.
- **Harness casualties (now recovered):** `meriyah`, `koota-pair` were zeroed by
  format-abort/empty-patch (koota-pair since solved by glm; meriyah's best 48/49 stands).
- **Solved by ≥1 model (11):** fastapi-deprecation, fastapi-implicit, pebble, kombu, updo,
  kea, prometheus, mashumaro, koota-pair, wasmi, awilix.
- **Still open for everyone (12):** bandit, csstree, effect-sse, gql, httpx-multipart,
  httpx-streaming, ink-grid, koota-deferred, meriyah, obsidian-link, pest, termenv.

## Arm status

| Arm | Graded | Solved in arm |
|---|---|---|
| gufo `failed23` | 22/22 | 3 — fastapi-deprecation, fastapi-implicit, pebble |
| maya-glm5-m `failed23` | 19/22 | 8 — kombu, updo, kea, prometheus, mashumaro, koota-pair, fastapi-deprecation, pebble (3 still outstanding after the uv-504 setup failures: fastapi-implicit, httpx-multipart, httpx-streaming) |
