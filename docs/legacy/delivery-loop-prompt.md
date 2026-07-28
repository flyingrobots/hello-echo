# Legacy Delivery Loop Prompt

<!-- markdownlint-disable MD013 MD025 -->

Status: **operative as a human-directed delivery protocol**.

Replacement status: `docs/phase-graph.md` is a specification, not a runtime.
This prompt remains the execution protocol until the external-action boundary,
Edict program, and negative envelope tests are implemented and pass. It is not
authoritative for roadmap ordering. `docs/roadmap.md` restores Pure Hello Echo
as Roadmap A and moves this loop to Roadmap Ω.

The target replacement uses three categories: deterministic law, external
interaction, and judgment. Edict emits typed requests; Echo records requests
before execution and settlements before resumption; adapters alone touch the
world. Models return untrusted proposal data and receive no mutation authority.
The later operator authorization to use administrative merge was an
execution-specific override and is not folded into this preserved baseline.

Operative addenda recorded after the baseline prompt:

- GitHub issue dependency reads and writes use the GraphQL API.
- Graft source-reading tools may assist bounded inspection but do not replace
  Git or GitHub state.
- The current human-directed run may use administrative merge. The target
  self-hosted program still excludes that capability because its requested
  negative-test suite requires rejection.
- Roadmap ordering and the external-action invariants are owned by
  `docs/roadmap.md`; the baseline prompt below remains the preserved
  human-directed execution protocol until Roadmap Ω passes its negative
  envelope tests.

---

# Autonomous Delivery Loop — Roadmap A → Roadmap B

## Autonomy Envelope

Read this first. It bounds everything below.

**Permitted without asking:** create branches, commit, push feature branches, open PRs, comment on PRs and issues, create and edit issues, create and edit milestones, set issue dependencies, resolve bot-authored review threads, merge a PR when the merge gate opens.

**Forbidden:** force-push any branch; push directly to `main`; rewrite published history; delete remote branches other than the just-merged feature branch; `gh pr merge --admin`; disable or skip CI; edit CI workflow files as a fix for a failing check; close a human-authored thread or issue.

**Escalate and stop:** any Forbidden action appears necessary; the same task fails three consecutive Phase-1 iterations; a merge gate closes on the same criterion twice; a required repo, label, or milestone cannot be created; total loop budget exhausted.

Escalation format:

```text
🛑 ESCALATION — <phase>: <condition>
Task:        <repo>#<issue> — <title>
Attempts:    <n>
Evidence:    <failing check, thread ID, test name, or command output>
Blocked on:  <the single decision required from the operator>
```

Stop. Do not attempt a workaround.

## Loop Budget

- Max 8 task iterations per invocation, then stop and report.
- Max 3 Phase-1 remediation iterations per task.
- Max 2 Code Lawyer passes per PR.
- Max 15 minutes total bot-review wait per PR.

On any budget exhaustion, finish the current commit, push, and report state. Never leave the worktree dirty.

## Definitions

- **BAD CODE™** — a defect, smell, or violation observed in an existing repo during any prior or current session. Filed as an issue labeled `bad-code`.
- **COOL IDEAS™** — a capability or design improvement not required by the current roadmap. Filed as an issue labeled `cool-idea`, and always assigned to Roadmap B unless it blocks Roadmap A.
- **Roadmap A** — `flyingrobots/hello-echo`. Must complete before Roadmap B work begins.
- **Roadmap B** — Graft written in Edict, hosted by Echo. Spans `flyingrobots/graft`, `flyingrobots/edict`, `flyingrobots/echo`.
- **Critical path** — the dependency-ordered chain of open issues whose completion is required for the earliest incomplete milestone on the active roadmap.
- **Active roadmap** — Roadmap A while any Roadmap A milestone remains open; Roadmap B thereafter.

## Repo Routing

Every task resolves to exactly one repo before execution. Ambiguity escalates.

| Work | Repo |
| --- | --- |
| Roadmap A implementation | `hello-echo` |
| Cross-repo coordination, dependency tracking | `hello-echo` (tracking issues only, no code) |
| Edict language, compiler, DSL surface | `edict` |
| Echo runtime, hosting, execution seam | `echo` |
| Graft itself | `graft` |

A task touching two repos is split into one issue per repo with an explicit `blocked-by` dependency. Never open a PR spanning repos.

## Phase A: Bootstrap (idempotent — safe to re-run)

1. **Repo exists.** Check `gh repo view flyingrobots/hello-echo`. If absent, create it: public, Apache-2.0, no auto-init. If present, do not modify its settings.
2. **Local repo.** In `./hello-echo`: if `.git` is absent, `git init -b main`. If present, leave history alone.
3. **Remote.** Set `origin` to `git@github.com:flyingrobots/hello-echo.git`. If `origin` exists and points elsewhere, escalate — do not silently rewrite it.
4. **Required files.** Ensure each exists; create only if missing, never overwrite:
   - `LICENSE` — Apache 2.0 full text, copyright James Ross.
   - `README.md` — project name, one-paragraph purpose, its role as prerequisite to Roadmap B, build and test commands.
   - `.gitignore` — appropriate to the detected stack (Rust, TypeScript/Node, or both).
   - `CHANGELOG.md` — Keep a Changelog format, `## [Unreleased]` section present.
5. **Labels.** Ensure `bad-code`, `cool-idea`, `roadmap-a`, `roadmap-b`, `blocked` exist.
6. **Publish.** Stage explicit paths, commit `chore: initialize repository scaffolding`, push with `-u origin main`.
7. **Branch protection check.** Record whether `main` requires PR review. If it does and no second collaborator exists, note this — it determines the merge gate's approval criterion below.

Echo bootstrap state: repo URL, whether created or pre-existing, files created, files already present, branch protection status.

## Phase B: The Loop

### Step 1 — Backlog Maintenance

1. File any outstanding BAD CODE™ and COOL IDEAS™ as issues in the routed repo, labeled per Definitions. Skip any that duplicate an existing open issue — match on title similarity and file path.
2. Set dependencies between issues using GitHub's native `blocked by` relationships. Where unsupported, record a `Blocked by: <repo>#<n>` line in the issue body and apply the `blocked` label.
3. Maintain one tracking issue per cross-repo dependency in `hello-echo`, listing both endpoints and current status.

### Step 2 — Roadmap Maintenance

1. Assign every unassigned open issue to a milestone on its roadmap. Create milestones only when no existing one fits; name them for the capability they deliver, not for dates.
2. Enforce the roadmap ordering: no Roadmap B issue may be assigned to a milestone that precedes the final Roadmap A milestone.
3. Report any dependency cycle and escalate. Do not break a cycle by guessing.

### Step 3 — Task Selection

1. Select the highest-priority open issue on the critical path of the **active roadmap** with all dependencies closed.
2. If the active roadmap has no unblocked open issue, report the blocking set and stop. Do not cross to the other roadmap early.
3. Echo the selection: repo, issue number, title, milestone, why it is on the critical path.

### Step 4 — Task Execution

#### 4.0 Branch

From a freshly fetched `origin/main`:

```bash
git switch -c task/<issue-number>-<kebab-slug> origin/main
```

Halt if the worktree is dirty before branching. All subsequent work happens on this branch. Never commit to `main`.

#### 4.1 Phase 1 — RED/GREEN/Self-Review

Write RED tests before any implementation. Not one test — a suite covering:

- golden path(s)
- known failure mode(s)
- boundary and edge cases
- property or fuzz cases, with a fixed seed recorded in the test
- stress case(s), bounded so they run in CI

Then iterate, max 3 passes:

1. Commit the RED tests. Verify they fail for the intended reason, not a compile error.
2. Implement until green. Commit.
3. Reconcile the documentation corpus against the change. Commit separately.
4. Append one `CHANGELOG.md` entry under `## [Unreleased]`. Commit separately.
5. Run **Self Code Review** (see Call Interface). Findings at `P0`–`P2` re-enter this loop at step 2. `P3`–`P4` are fixed in place without new tests. `P5` is recorded on the issue and not fixed.
6. Exit when a pass yields no finding above `P4`.

On the third pass still yielding a `P0`–`P2`, escalate.

#### 4.2 Push and open PR

```bash
git push -u origin task/<issue-number>-<slug>
gh pr create --base main --fill --body "<intent>. Closes #<issue-number>."
```

Commit messages and PR body: terse, systems-oriented, precise rule language. No narration.

#### 4.3 Phase 2 — Bot review, bounded

1. Request review: post `@coderabbitai review`, then `@codex please review`.
2. Poll every 60s. A reviewer is **done** when any of these holds: it posts a review or review comment; it posts a cooldown, rate-limit, or refusal notice; it reacts to the request comment and 5 minutes elapse with no review; 15 minutes elapse in total.
3. A reaction alone is acknowledgment, not completion. Never treat a 👍 as a finished review.
4. When all reviewers are done, run **Code Lawyer** (see Call Interface).
5. Push. If new bot threads appeared, run a second Code Lawyer pass. Never a third — escalate instead.

#### 4.4 Merge gate

Code Lawyer reports the gate; the orchestrator acts on it.

Gate criteria, evaluated in order:

1. All CI checks passing, none queued or in progress.
2. No unresolved bot-authored review threads.
3. All Code Lawyer outcomes are `FIXED`, `DEFERRED`, `STALE`, or `UNREPRODUCIBLE`. Any `BLOCKED` closes the gate.
4. Local suite and all linters clean, excluding the recorded baseline.
5. **Approval.** If `main` requires review and a non-bot collaborator other than the author exists, that approval is required. If the repo is solo-maintained and branch protection does not require review, criteria 1–4 substitute for human approval — record this substitution explicitly in the merge comment.

Gate open:

```bash
gh pr merge --squash --delete-branch
```

Gate closed: report the failed criterion with evidence and escalate. Never `--admin`. Never merge on red CI.

### Step 5 — Sync and Loop

1. `git switch main && git pull --ff-only origin main`
2. `git fetch --prune` to clear the deleted remote branch.
3. Delete the local task branch.
4. Verify the issue closed. If it did not, close it with a reference to the merge commit.
5. Confirm the worktree is clean. If not, escalate — do not clean it.
6. Decrement the task budget. If budget remains and the active roadmap has unblocked work, return to Step 1. Otherwise report and stop.

## Call Interface for Sub-Protocols

Both protocols live as files, not inline text: `.agent/self-code-review.md` and `.agent/code-lawyer.md`.

**Shared severity ladder.** Both use one vocabulary — `P0` Critical, `P1` High, `P2` Medium, `P3` Low, `P4` Nit, `P5` Defer. The `CRITICAL/HIGH/MEDIUM/LOW/NIT` labels are retired.

**Self Code Review — required deltas:**

- Phase 5 (PR comment) is skipped when invoked from 4.1; no PR exists yet.
- Phase 7 does not ask permission. When `AUTONOMOUS=true`, emit the remediation plan and return it to the caller. The orchestrator decides.
- Phase 0's clean-tree gate is satisfied by 4.1 steps 1–4 committing first.

**Code Lawyer — required deltas:**

- Phase I.2 self-audit is **skipped** when Self Code Review already ran on this diff at the current `HEAD`. Only PR-sourced threads enter the queue. Re-auditing the same diff wastes the budget and produces duplicate findings.
- Phase IV is report-only. Delete any merge instruction from it; the orchestrator holds merge authority.
- Phase IV.3 approval criterion defers to orchestrator 4.4.5.

## Final Report

- Bootstrap outcome.
- Issues created, by label and repo.
- Milestones created or modified.
- Tasks attempted, with PR URL, merge status, and iteration count each.
- Budget consumed, per counter.
- Open escalations, or `none`.
- Active roadmap and next unblocked task.

<!-- markdownlint-enable MD013 MD025 -->
