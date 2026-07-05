# Audit Fix Program — Master Execution Strategy

> **For agentic workers:** This is the program-level document for the six-wave audit fix effort. It defines wave ordering, the execution model, review gates, and rollback strategy. Each wave has its own implementation plan in this directory; execute waves strictly in order, one plan at a time, via superpowers:subagent-driven-development with the model assignments below.

**Source:** July 2026 repository audit (6 Opus 4.8 xhigh explorer agents + 1 Fable 5 adversarial verifier), 55 verified findings at commit `852b689`. Full report: https://claude.ai/code/artifact/ad543843-ffbb-4867-a6fe-e52bd8c5f0a7

**Goal:** Land all 55 verified findings across six sequential waves, each on its own branch with its own PR to `main`, ordered so correctness lands before optimization and the real-Neovim test tier lands before the engine work that needs it.

---

## Waves

| Wave | Plan | Branch | Findings | Scope |
|------|------|--------|----------|-------|
| 1 | `2026-07-05-wave-1-quick-wins.md` | `audit/wave-1-quick-wins` | #1 #6 #13 #7 #25 #8 #28 #34 V2 (9) | Trivial/small correctness fixes; closes issue #14 and every state leak |
| 2 | `2026-07-05-wave-2-vim-fidelity.md` | `audit/wave-2-vim-fidelity` | #2 #3 #4 #9 #10 #11 #12 #14 #26 #27 V1 V3 (12) | Synchronous-finalization guard; calculator semantics (folds, multibyte, jumplist, curswant, 'scroll') |
| 3 | `2026-07-05-wave-3-test-tier-ci.md` | `audit/wave-3-test-tier-ci` | #5 #18 #49 (3) | Real-Neovim integration tier, GitHub Actions CI, stylua/luacheck |
| 4 | `2026-07-05-wave-4-engine-internals.md` | `audit/wave-4-engine-internals` | #15 #16 #29 #30 #31 #32 #33 #35 #37 (9) | Frame-loop optimizations, eventignore wiring, window-scoped domination |
| 5 | `2026-07-05-wave-5-polish-seams.md` | `audit/wave-5-polish-seams` | #20 #48 #47 #45 #46 #36 #17 #38 #39 #40 #41 #50 #51 #52 (14) | Vimdoc, checkhealth, LuaCATS, keymap restore, registry seams, contributor surface |
| 6 | `2026-07-05-wave-6-features.md` | `audit/wave-6-features` | #19 #21 #22 #23 #24 #42 #43 #44 (8) | User events, exclusions, animate_to API, new motions, easing/duration features |

Finding refs resolve to the audit report; each wave's plan restates its findings in full, so executors never need the report.

---

## Execution model (fixed for all waves)

- **Branching:** each wave branches from `main` only after the previous wave's PR has merged. Never stack wave branches.
- **Executor:** one Sonnet 5 subagent (high effort) per task, fresh context per task. The executor receives only: the plan header, Global Constraints, and its single task text. No exploration — paths and code are in the task.
- **Task review gate:** after each task, an Opus 4.8 subagent (xhigh effort) reviews the task's diff (`git diff HEAD~1`) against the task spec. Verdict gates progression: `approve` → next task; `reject` → executor retry with the review findings appended (max two retries, then escalate to the orchestrator).
- **Wave review gate:** when all tasks are complete and both test tiers pass, one Fable agent reviews the full branch diff (`git diff main...HEAD`) against the wave plan plus its findings file. Its findings are fixed on the branch before the PR opens.
- **PR:** to `main`, squash-merge. Title `Wave N: <name>`; body lists findings fixed (Wave 1 includes `Fixes #14`), links the plan, and summarizes the Fable review outcome. No AI attribution anywhere in commits or PR bodies.
- **Orchestrator:** the main session drives superpowers:subagent-driven-development, verifies every executor claim against git artifacts (diffs, test output), and never trusts narration.
- **Plan staleness rule:** all six plans were authored concurrently against commit `852b689`. A later wave's listings may show surrounding code as it existed before earlier waves changed it (the contracts table below says what changed when). The task's NEW behavior is authoritative; the surrounding code is not. Executors graft the new behavior onto the branch's current code, task reviewers reject any diff that reverts an earlier wave's change, and absolute test counts in plans are read as deltas (the parenthesized arithmetic) against the branch's actual pre-task count. Waves 5 and 6 have been reconciled against Waves 1–4's final plans where drift was concrete; the rule still applies to anything missed.

## Step 1 — Dependency analysis

Waves are **strictly sequential**; the plugin is ~2,100 lines and the same core files recur across waves:

| File | Touched in waves |
|------|------------------|
| `engine/orchestrator.lua` | 1, 2, 4, 5, 6 |
| `engine/loop.lua` | 2, 4, 6 |
| `performance.lua` | 1, 2, 4 |
| `calculators/scroll.lua` | 2, 6 |
| `registry/keymaps.lua` | 1, 5 |
| `registry/builtin.lua` | 2, 6 |
| `config/*` | 1, 5, 6 |

Cross-wave contracts (defined once, consumed later — see each plan's Interfaces blocks):

1. `has_count` input field — introduced Wave 1, consumed by Waves 2 and 6.
2. `calculators/native.lua` shared delegation helper (returns cursor + curswant) — introduced Wave 2, optimized Wave 4, consumed Wave 6.
3. `jump = true` motion flag + `m'` jumplist push — introduced Wave 2, applied to new motions in Wave 6.
4. `should_skip_animation(context)` seam — introduced Wave 2 (macro guard), extended Wave 6 (exclusions, min_distance).
5. Per-`(trait, winid)` animating state + `loop.complete_for_window` — introduced Wave 4.
6. Config keys always land as defaults + validation together.

## Step 2 — Risk classification

| Wave | Risk | Why | Mitigation |
|------|------|-----|------------|
| 1 | LOW-MED | Small, local fixes; one input-contract addition | Mock-tier tests + headless probes per task |
| 2 | HIGH | Async behavior, hot-path semantics, calculator rewrites | Headless probe per task; git tag `pre-wave-2` before starting; Wave 3 pins everything as permanent regressions |
| 3 | MED | Infra only, but CI must be green on 0.8.3/stable/nightly | Dry-run workflow via `act` optional; verify on the PR itself |
| 4 | HIGH | Hot-path optimization can regress behavior subtly | Integration tier from Wave 3 must stay green; tag `pre-wave-4` |
| 5 | LOW-MED | Mostly additive docs/seams; keymap restore touches UX | maparg snapshot tests |
| 6 | MED-HIGH | New public API + config surface | Validation-first tasks; integration specs per feature |

Per the program owner's directive, executor/reviewer models are uniform across risk levels (Sonnet 5 high / Opus 4.8 xhigh / Fable per wave); risk instead drives the tags, probe density, and how much scrutiny the orchestrator applies to review verdicts.

## Step 3 — Parallelization

None, deliberately. Within a wave, tasks share files and each task's review gates the next; across waves, contracts and shared files force sequence. The parallelism in this program lives in review (executor and reviewer are different agents) — not in concurrent edits. One executor per working tree at all times.

## Step 4 — Agent allocation

| Role | Model | Effort | Count | Context given |
|------|-------|--------|-------|---------------|
| Task executor | Sonnet 5 | high | 1 per task, fresh | Plan header + Global Constraints + one task |
| Task reviewer | Opus 4.8 | xhigh | 1 per task, fresh | Task text + `git diff HEAD~1` + test output |
| Wave reviewer | Fable 5 | xhigh | 1 per wave | Wave plan + findings file + `git diff main...HEAD` |
| Orchestrator | main session | — | 1 | Everything; verifies against git |

## Step 5 — Token discipline

- Executors get exact paths and complete code from the plan — zero exploration.
- Reviewers get the diff, not the repo tour; they may open cited files to check call sites.
- Wave reviewer reads the branch diff once, not per task.
- `git mv`/`git rm` for renames and deletions (Wave 5 dead-code task).

## Step 6 — Error prevention and rollback

- **Gates per task:** `bash scripts/run_tests.sh` green (and `bash scripts/run_nvim_tests.sh` from Wave 3 on) before every commit; commit style enforced by review.
- **Gates per wave:** both test tiers green, stylua/luacheck clean (Wave 3+), Fable review passed, then PR; CI green on the PR before merge.
- **Tags:** `git tag pre-wave-2` and `git tag pre-wave-4` on `main` before those waves branch.
- **Rollback:** pre-merge → abandon the branch; post-merge → revert the squash commit. Waves are independent enough that a reverted wave only blocks its dependents (contracts table above says which).
- **Trust artifacts:** orchestrator verifies executor claims via `git log`/`git diff` and re-runs the gates itself before opening each PR.

## Step 7 — Review prompt templates

**Task reviewer (Opus 4.8, xhigh):**
> Review this diff against the task spec below. The diff must implement exactly the task — no scope creep, no placeholder code, tests included and passing (output attached). Check: spec conformance, correctness of the Lua against Neovim >= 0.8 API, test quality (does the test actually pin the fixed behavior?), style (two-space indent, no inline comments, conventional commit). Verdict: `approve` or `reject` with specific, actionable findings.

**Wave reviewer (Fable 5):**
> You are reviewing the complete branch diff for Wave N against its plan and findings file. For every finding ref: locate the change that resolves it and judge whether it actually fixes the described failure scenario. Hunt for regressions the per-task reviews could miss: cross-task interactions, contract violations against the master strategy doc, behavior changes outside the wave's scope. Run both test suites yourself. Verdict: `ready-for-pr` or a list of required fixes.
