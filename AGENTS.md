# AGENTS.md — Working Memory Snapshot

## Mission

Build a local-first macOS app that helps founder/coders return to deep work in under 60 seconds.

The canonical product loop is:

```text
project → session → evidence → brain dump → snapshot → resume
```

The app is a cognitive-continuity tool. It is not a generic Pomodoro timer, task manager, note app, employee-monitoring system, or general AI chat client.

## Required context

Before any implementation task, read:

- `docs/00-product-prd.md`
- `docs/01-system-architecture.md`
- `docs/05-mvp-roadmap.md`
- `docs/06-codex-workflow.md`
- `docs/07-macos-build-compile.md`

Then read the task-relevant documents:

- UI work: `docs/02-ui-spec.md`
- Persistence work: `docs/03-data-model.md`
- LM Studio or prompting work: `docs/04-local-ai-spec.md`
- Tests: `docs/07-testing-strategy.md`
- Architectural choices: `docs/08-decision-log.md`
- Risk-sensitive work: `docs/09-risk-register.md`

Do not claim to have read a file you did not inspect.

## Product invariants

1. Preserve cognition, not activity.
2. Local data stays local.
3. The app remains calm during a session.
4. Observation occurs only while a session is active.
5. Observe only the selected project folder, Git metadata, app activation, and user-entered text.
6. Do not capture keystrokes, screenshots, clipboard contents, browser history, messages, or files outside the selected project.
7. Prefer hard evidence to inference.
8. A generated decision must be supported by the brain dump or evidence; otherwise omit it.
9. The snapshot must fit comfortably on one screen.
10. Every feature must reduce restart friction or be deferred.

## Technical invariants

1. Use native Swift and SwiftUI for macOS.
2. Use AppKit bridges only where macOS APIs require them.
3. Use local SQLite behind repositories.
4. For MVP, App Sandbox is off and selected project paths are persisted locally.
5. Store an optional LM Studio API token in Keychain, never SQLite or source control.
6. Use LM Studio's local OpenAI-compatible API.
7. Keep observed activity in a generic `Event` model; do not add tool-specific Cursor, Codex, Claude, or VS Code tables.
8. Use deterministic event compaction in the minimal usable increment.
9. Keep local-model HTTP logic in `LMStudioClient`.
10. Keep prompts and JSON schemas in `PromptBuilder`.
11. Keep views thin; screen state belongs in `@MainActor` view models.
12. Serialize mutable persistence and observation state through actors or another explicit concurrency boundary.
13. Do not add production dependencies without recording the rationale in `docs/08-decision-log.md`.
14. Do not enable App Sandbox, change signing, or change build settings unless the task explicitly requires it.

## macOS Build & Compile Rules

Before changing build configuration, read:

- `docs/07-macos-build-compile.md`

Preserve these defaults unless explicitly instructed otherwise:

```text
Project: WorkingMemorySnapshot.xcodeproj
Scheme: WorkingMemorySnapshot
Bundle ID: com.broceps.WorkingMemorySnapshot
Minimum macOS target: 14.0
Swift language mode: Swift 5
Persistence: SQLite through system SQLite3
Runtime AI: LM Studio local server
App Sandbox: off for MVP
LM Studio required for compile: no
```

Do not modify `project.pbxproj` unless required to add files/resources to the target, link required config/library settings, or explicitly requested. Prefer `.xcconfig`, source files, docs, and scripts.

## Scope discipline

Implement one milestone or focused task at a time.

Do not:

- implement later milestones opportunistically
- add speculative abstractions
- perform unrelated refactors
- rename broad areas without a requirement
- expand the data model “for the future”
- add analytics, accounts, cloud sync, notifications, or deep tool integrations

When needed work is outside scope, record it in the final report as a follow-up rather than implementing it.

## Git workflow

Treat Git hygiene as part of the task.

Before edits:

```bash
git status --short
git branch --show-current
```

Rules:

1. Never implement directly on `main`.
2. If the task runs in a detached Codex worktree, create the specified branch before the first commit.
3. One branch contains one coherent milestone or leaf task.
4. Do not stage unrelated user changes.
5. Keep commits atomic and reviewable.
6. Use conventional-style messages:
   - `feat: ...`
   - `fix: ...`
   - `test: ...`
   - `refactor: ...`
   - `docs: ...`
   - `chore: ...`
7. Run the required checks before committing.
8. Review `git diff --stat` and the relevant full diff.
9. Codex may create local branches and commits.
10. Codex must not push, merge, delete branches, rewrite history, or open a pull request unless explicitly instructed.

If the worktree is dirty with changes unrelated to the task, preserve them and report the conflict. Do not reset, clean, stash, or overwrite them without instruction.

## Validation

Use:

```bash
./scripts/check.sh
```

For fast pre-commit checks:

```bash
./scripts/check.sh --quick
```

Run targeted tests in addition to the standard script when the task warrants them.

Do not report success when the build or tests failed. Preserve the exact failure and explain what remains.

## Commit gate

Commit only when:

- acceptance criteria are satisfied
- relevant automated checks pass
- the diff is scoped
- no secrets, user data, database files, or generated build artifacts are staged
- known limitations are documented

## Final response format

End implementation tasks with:

```text
Branch:
<name>

Commit:
<hash, or “not committed” with reason>

What changed:
- ...

Validation:
- command — result

Manual test:
1. ...
2. ...

Files changed:
- ...

Notes / limitations:
- ...

Suggested next task:
- ...
```

## Parallel work

Do not parallelize architecture or the initial vertical slice.

After M4 is merged, separate Codex worktrees may implement M5 leaf services. Two threads must not modify the same files. Integration returns to one serial branch.

Use the repository skill for implementation tasks:

```text
$milestone-execution
```
