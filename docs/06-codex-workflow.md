# Working Memory Snapshot — Codex Development Workflow

## 1. Purpose

Codex should behave like a disciplined engineer operating in a reviewable Git workflow, not like an unbounded code generator.

The default loop is:

```text
read context
→ inspect repository
→ verify clean starting state
→ create or confirm branch
→ plan
→ implement a bounded task
→ test
→ review diff
→ commit
→ report
```

Build-specific rules live in `docs/07-macos-build-compile.md`. Read that file before changing Xcode project settings, signing, sandboxing, Swift mode, deployment target, plist values, or validation scripts.

## 2. Repository guidance

Codex automatically reads `AGENTS.md`. Implementation prompts should also invoke:

```text
$milestone-execution
```

The skill translates the workflow into repeatable execution steps.

## 3. Starting-state protocol

Before editing:

```bash
git status --short
git branch --show-current
git rev-parse --show-toplevel
```

Then:

- verify the expected repository
- inspect relevant docs and existing patterns
- identify the acceptance criteria
- confirm the task branch
- state a short plan

If unrelated local changes exist:

- do not reset
- do not clean
- do not stash
- do not overwrite
- limit edits to non-conflicting files when safe
- otherwise stop and report the collision

## 4. Branching

Never implement on `main`.

Naming:

```text
feature/m<N>-short-description
feature/m<N><letter>-short-description
fix/short-description
docs/short-description
test/short-description
chore/short-description
```

A branch contains one coherent outcome.

When Codex starts in a worktree with detached HEAD:

```bash
git switch -c <task-branch>
```

before committing.

## 5. Parallel threads and worktrees

Parallel work is allowed only after M4.

Use separate worktrees for M5 leaf services. All worktrees start from the same clean `main` commit.

Before dispatching parallel work, define:

- branch name
- exact files or directories owned
- interfaces consumed
- files that must not be changed
- acceptance criteria
- validation commands

Avoid two threads editing the same files. Do not parallelize:

- database architecture
- navigation architecture
- session lifecycle
- global state
- integration
- migration changes

After leaf branches are ready, return to a single integration branch.

## 6. Planning

The plan should be short and implementation-specific:

- files to inspect
- types or boundaries to add
- tests to write
- validation to run
- notable risk

Do not spend a task producing a speculative redesign when implementation is requested.

## 7. Scope control

Codex must not implement unrelated “helpful” work.

A task may include a small prerequisite only when:

- it is required to satisfy acceptance criteria
- it is documented in the plan
- it does not introduce a new product capability
- it is tested

Everything else becomes a suggested follow-up.

## 8. Commits

Commit only accepted, validated work.

Preferred messages:

```text
feat: persist user-selected projects
feat: add LM Studio model discovery
fix: handle inaccessible project folders
test: cover snapshot response decoding
docs: record sandbox decision
```

Avoid vague messages.

Use multiple commits only when they form independently reviewable steps. Do not create artificial micro-commits for every file.

## 9. Staging

Review before staging:

```bash
git diff --stat
git diff
```

Stage explicit paths when unrelated files exist.

Before commit:

```bash
git diff --cached --stat
git diff --cached
./scripts/check.sh
```

The pre-commit hook also runs fast checks.

Never commit:

- tokens or secrets
- local SQLite databases
- model files
- DerivedData
- user-specific Xcode state
- absolute machine-specific paths
- debug logs containing private evidence

## 10. Validation

The canonical command is:

```bash
./scripts/check.sh
```

For local environment diagnostics that must not affect compile success:

```bash
./scripts/doctor.sh
```

Use targeted commands in addition, for example:

```bash
xcodebuild test ...
```

The full check should build the app and run available tests once a project exists.

A failed check blocks commit unless the task explicitly documents an environment limitation and the user requested a partial handoff.

## 11. Documentation hygiene

Update docs when the implementation deliberately changes:

- product scope
- architecture
- schema
- API contract
- milestone acceptance criteria
- developer workflow

Record significant decisions in `docs/08-decision-log.md`.

Do not rewrite the PRD merely to match an accidental implementation choice.

## 12. Merge and remote safety

Codex may:

- create local branches
- create local commits
- prepare a PR-style summary

Codex must not, without explicit instruction:

- push
- force-push
- merge to `main`
- rebase shared history
- delete branches
- create or close pull requests
- change remotes
- tag releases

`main` should remain runnable.

## 13. Final report

Every implementation task returns:

```text
Branch:
...

Commit:
...

What changed:
- ...

Validation:
- ...

Manual test:
1. ...

Files changed:
- ...

Notes / limitations:
- ...

Suggested next task:
- ...
```

Include exact failed commands when validation is incomplete.

## 14. Definition of done

A task is done when:

- requested behavior exists
- acceptance criteria are met
- tests cover important logic
- build/check passes
- diff contains no unrelated changes
- docs match deliberate decisions
- commit is created
- final report is complete

“Code was written” is not done.
