# Working Memory Snapshot

Working Memory Snapshot is a local-first macOS app that helps founder/coders return to deep work without rebuilding the project context they were holding.

The app supports the complete local workflow:

```text
project → session → evidence → brain dump → snapshot → resume
```

It also provides an on-demand Daily Rollup across completed project sessions, with project threads, carry-forwards, source-session drill-down, and preserved history for every generated revision.

## What it does

- Adds local project folders through the native macOS folder picker.
- Runs one recoverable work session at a time with lightweight focus blocks.
- Captures bounded file-path, Git, active-app, and user-entered evidence only while a session is active.
- Generates structured Working Memory Snapshots through a local LM Studio model.
- Keeps the latest Resume Brief and next action visible from each project.
- Generates a whole-day rollup across projects without scores, streaks, or task-manager semantics.
- Stores app data in local SQLite and an optional LM Studio token in Keychain.

The app has no cloud backend, account, analytics, screenshots, keystroke capture, clipboard capture, browser-history capture, or message ingestion.

## Requirements

- Runtime target: macOS 14 or later.
- Source-build host: a macOS release supported by Xcode 26 or later.
- Xcode 26 or later, including its Command Line Tools.
- Git.
- LM Studio only for snapshot and Daily Rollup generation. It is not required to compile, test, launch, or explore the rest of the app.

There are no third-party Swift packages or production dependencies to install.

This repository provides a source build for local development; it does not currently publish a signed or notarized app release.

## Quick start from a clone

```bash
git clone https://github.com/zkissing94/working-memory-snapshot.git
cd working-memory-snapshot
./scripts/doctor.sh
./scripts/check.sh
open .derivedData/Build/Products/Debug/WorkingMemorySnapshot.app
```

Quit any running copy of Working Memory Snapshot before `./scripts/check.sh`; the test host must launch the single-instance app itself.

The full check builds the shared `WorkingMemorySnapshot` scheme with signing disabled and runs the complete automated test suite. LM Studio and internet access are not used by the tests.

Contributors can optionally install the repository's pre-commit hook with `./scripts/install_hooks.sh`.

To work in Xcode instead, open `WorkingMemorySnapshot.xcodeproj`, select the shared `WorkingMemorySnapshot` scheme, and run the macOS target.

## Configure local generation

1. Install LM Studio, load a local instruct model that can follow a structured JSON schema, and start its local server.
2. The app defaults to `http://localhost:1234/v1`.
3. Open Settings in Working Memory Snapshot.
4. Choose **Refresh Models**, select the loaded model, then choose **Test Connection** and **Save**.
5. Add a bearer token only when the local server is configured to require one. The token is stored in Keychain, never SQLite.

The same selected model generates both project snapshots and Daily Rollups. A failed generation preserves the completed session, brain dump, and any prior generated artifact.

## First run

1. Add a project folder from the sidebar.
2. Start a session and enter a concrete mission.
3. Work normally, optionally recording notes, decisions, or blockers in a focus block.
4. End the session with a short brain dump.
5. Generate and review the project snapshot.
6. Open Daily Rollup after completing sessions to synthesize the day across projects.

## Local data and privacy

- SQLite database: `~/Library/Application Support/WorkingMemorySnapshot/working-memory.sqlite3`
- Optional LM Studio token: macOS Keychain
- Runtime model endpoint: loopback by default
- Selected project access: local path-based access with App Sandbox off for the current MVP
- Focus-block alerts: optional local notification permission; the in-app completion prompt still works when permission is declined

Local databases, journals, build output, secrets, and Xcode user state are ignored by Git. Deleting a source checkout does not delete the app database in Application Support.

## Validation and troubleshooting

```bash
./scripts/check.sh --quick  # repository and script checks
./scripts/check.sh          # build and complete test suite
./scripts/doctor.sh         # local toolchain and optional LM Studio diagnostics
```

Build and signing constraints are documented in [`docs/07-macos-build-compile.md`](docs/07-macos-build-compile.md). The latest delivered state and known follow-ups are recorded in [`docs/10-current-status.md`](docs/10-current-status.md).

## Developing with Codex

Read [`CODEX_START_HERE.md`](CODEX_START_HERE.md) and the root [`AGENTS.md`](AGENTS.md). The repository already contains the Xcode project and implementation; do not recreate the project or replay the historical milestone prompts on top of the current branch.

## Canonical documents

- [`docs/00-product-prd.md`](docs/00-product-prd.md)
- [`docs/01-system-architecture.md`](docs/01-system-architecture.md)
- [`docs/02-ui-spec.md`](docs/02-ui-spec.md)
- [`docs/03-data-model.md`](docs/03-data-model.md)
- [`docs/04-local-ai-spec.md`](docs/04-local-ai-spec.md)
- [`docs/05-mvp-roadmap.md`](docs/05-mvp-roadmap.md)
- [`docs/06-codex-workflow.md`](docs/06-codex-workflow.md)
- [`docs/07-macos-build-compile.md`](docs/07-macos-build-compile.md)
- [`docs/07-testing-strategy.md`](docs/07-testing-strategy.md)
- [`docs/08-decision-log.md`](docs/08-decision-log.md)
- [`docs/09-risk-register.md`](docs/09-risk-register.md)
- [`docs/10-current-status.md`](docs/10-current-status.md)

## License

No open-source license has been selected. Treat the source as all rights reserved unless the repository owner grants permission.
