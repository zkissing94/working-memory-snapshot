---
name: milestone-execution
description: Execute a scoped implementation milestone or focused engineering task in this repository with branch isolation, planning, validation, atomic commits, and a PR-style final report. Use for code, tests, migrations, or implementation docs. Do not use for read-only product discussion.
---

# Milestone Execution

Follow these steps in order.

## 1. Load context

Read root `AGENTS.md`.

Read the four always-required documents:

- `docs/00-product-prd.md`
- `docs/01-system-architecture.md`
- `docs/05-mvp-roadmap.md`
- `docs/06-codex-workflow.md`

Read only the additional documents relevant to the task.

State any conflict between the task prompt and canonical docs before coding. The explicit current user task wins only when it clearly intends to change the spec; record that change.

## 2. Inspect safely

Run:

```bash
git status --short
git branch --show-current
git rev-parse --show-toplevel
```

Inspect existing source and tests before designing new patterns.

If unrelated user changes overlap the task, preserve them and report the collision. Never reset, clean, stash, or overwrite without instruction.

## 3. Establish the task branch

Never implement on `main`.

- Switch to or create the branch named in the task.
- In a detached worktree, create the named branch before committing.
- Do not rebase or rewrite history.
- Do not push.

## 4. Plan

Provide a short plan containing:

- files and interfaces to inspect
- implementation steps
- tests
- validation command
- main risk

Keep the plan bounded to the requested acceptance criteria.

## 5. Implement

- Follow existing patterns.
- Keep views thin.
- Keep I/O off the main actor.
- Preserve privacy boundaries.
- Avoid unrelated refactors.
- Add tests with behavior.
- Update canonical docs only for deliberate decisions.

## 6. Validate

Run targeted tests, then:

```bash
./scripts/check.sh
```

Review:

```bash
git diff --stat
git diff
```

Fix scoped failures. Never hide a failure.

## 7. Stage and commit

Stage explicit intended files.

Review:

```bash
git diff --cached --stat
git diff --cached
```

Commit only when acceptance criteria pass.

Use the task's commit message or a concise conventional message.

Do not push, merge, delete branches, open a PR, or modify remotes.

## 8. Report

Return:

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
