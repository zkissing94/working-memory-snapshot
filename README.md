# Working Memory Snapshot

Working Memory Snapshot is a local-first macOS app that helps founder/coders return to deep work without rebuilding the project context they were holding.

> **Download status:** The app is currently available as source code. There is no signed `.dmg` or notarized GitHub release yet, so the local setup below builds the app on your Mac with Xcode.

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

## Download and run locally

### What you need

- Runtime target: macOS 14 or later.
- Source-build host: a macOS release supported by Xcode 26 or later.
- Xcode 26 or later, including its Command Line Tools.
- Git, if you use the recommended clone workflow.
- LM Studio only for snapshot and Daily Rollup generation. It is not required to compile, test, launch, or explore the rest of the app.

There are no third-party Swift packages or production dependencies to install.

Before building for the first time, open Xcode once so it can install required components and finish its license/setup prompts.

### 1. Get the source

The recommended option is to clone the repository in Terminal:

```bash
git clone https://github.com/zkissing94/working-memory-snapshot.git
cd working-memory-snapshot
```

If you do not use Git, choose **Code → Download ZIP** on GitHub, unzip the download, and open Terminal in the extracted `working-memory-snapshot` folder.

### 2. Check, build, and launch

From the repository folder, run:

```bash
./scripts/doctor.sh
RUN_TESTS=0 ./scripts/check.sh
open .derivedData/Build/Products/Debug/WorkingMemorySnapshot.app
```

`doctor.sh` checks the local toolchain and explains any missing requirement. The build command compiles the shared `WorkingMemorySnapshot` scheme with signing disabled; it does not need LM Studio or internet access. The first build may take several minutes.

The built app remains at `.derivedData/Build/Products/Debug/WorkingMemorySnapshot.app` inside the checkout. To keep it somewhere more convenient, open that folder and drag the app to `Applications`:

```bash
open .derivedData/Build/Products/Debug
```

Rebuild from the latest source before replacing that copy; the repository does not currently provide automatic updates.

### Xcode option

To build interactively, open `WorkingMemorySnapshot.xcodeproj`, select the shared `WorkingMemorySnapshot` scheme and **My Mac** destination, then press **Run**.

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

Quit every running copy of Working Memory Snapshot before the full check; the test host must launch the single-instance app itself. The automated suite does not use LM Studio or internet access.

Common setup issues:

- If `doctor.sh` cannot run Xcode tools, finish Xcode's first-launch setup and confirm the active developer directory in **Xcode → Settings → Locations**.
- If the full check says the app is already running, quit Working Memory Snapshot and run the command again.
- If local generation is unavailable, the app itself can still launch. Start LM Studio's local server, load a compatible instruct model, and complete the Settings steps above when you are ready to generate snapshots.

Contributors can optionally install the repository's pre-commit hook with `./scripts/install_hooks.sh`.

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
