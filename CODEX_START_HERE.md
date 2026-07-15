# Continue Working Memory Snapshot with Codex

This repository is an implemented native macOS app, not a blank project seed. The Xcode project, shared scheme, source, migrations, tests, and validation scripts are already committed.

Do not initialize another Git repository, create another Xcode project, or replay the historical milestone prompts on top of the current implementation.

## 1. Clone and validate

Follow the prerequisites and quick start in [`README.md`](README.md). At minimum:

```bash
git clone https://github.com/zkissing94/working-memory-snapshot.git
cd working-memory-snapshot
./scripts/install_hooks.sh
./scripts/doctor.sh
./scripts/check.sh
```

Quit all running copies of Working Memory Snapshot before the full check. LM Studio is optional for compile and automated tests.

## 2. Open the repository in Codex

Open the repository root in the Codex app, CLI, or IDE extension. Codex automatically discovers [`AGENTS.md`](AGENTS.md).

The repository-scoped implementation skill is located at:

```text
.agents/skills/milestone-execution/SKILL.md
```

Invoke it for implementation work:

```text
$milestone-execution
```

## 3. Load the current context

Before making changes, read:

- `AGENTS.md`
- `docs/10-current-status.md`
- `docs/00-product-prd.md`
- `docs/01-system-architecture.md`
- `docs/05-mvp-roadmap.md`
- `docs/06-codex-workflow.md`
- `docs/07-macos-build-compile.md`

Then read only the task-relevant UI, data, local-AI, testing, decision, or risk documents named by `AGENTS.md`.

If `docs/10-current-status.md` conflicts with Git history, inspect Git and reconcile the status document before implementing.

## 4. Work on a focused branch

```bash
git status --short
git branch --show-current
git switch -c codex/<focused-task>
```

Keep one coherent task per branch. Preserve unrelated user changes, run targeted tests plus `./scripts/check.sh`, review the complete diff, and commit only validated work.

Codex may create local branches and commits. It must not push, merge, delete branches, rewrite history, or open a pull request unless the user explicitly requests that action.

## 5. Understand the historical prompts

The files in `prompts/` document how earlier milestones were built. They are useful implementation history and reference material, but they are not a setup sequence for a current clone.

Use [`prompts/99-task-template.md`](prompts/99-task-template.md) for a new scoped task, and use [`docs/10-current-status.md`](docs/10-current-status.md) for the current handoff.

## Current product boundary

The app is a local cognitive-continuity tool. Preserve these constraints when extending it:

- Native Swift and SwiftUI for macOS.
- Local SQLite and local LM Studio generation.
- Observation only while a session is active.
- No cloud backend, accounts, telemetry, screenshots, keystrokes, clipboard, browser history, or message ingestion.
- No task scoring, streaks, employee monitoring, or generic AI chat behavior.
