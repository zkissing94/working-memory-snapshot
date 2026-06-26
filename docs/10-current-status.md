# Working Memory Snapshot - Current Status

## Where the project is

Current handoff branch:

```text
feature/m4-placeholder-snapshot
```

Completed milestones:

- M0 - Repository seed and Codex workflow
- M1 - App shell, build foundation, and project persistence
- M2 - LM Studio settings and model discovery
- M3 - Session lifecycle
- M4 - Placeholder snapshot vertical slice

Current implementation state:

- Native SwiftUI macOS app scaffold exists.
- Shared `WorkingMemorySnapshot` scheme is committed.
- Build settings are pinned through `Config/*.xcconfig`.
- Explicit `WorkingMemorySnapshot/Resources/Info.plist` is committed.
- `./scripts/check.sh` builds and tests with signing disabled.
- SQLite project persistence works with path-based project access while App Sandbox is off for MVP.
- Settings persistence works through `app_settings`.
- LM Studio base URL and selected synthesizer model persist locally.
- Optional LM Studio API token is stored in Keychain, not SQLite.
- Settings UI supports base URL, synthesizer model, optional token, connection testing, model refresh, and non-loopback warning.
- `LMStudioClient` lists models through `GET /v1/models` with optional bearer authentication.
- Automated M2 tests cover URL normalization, loopback warning logic, settings persistence, token privacy, bearer headers, and distinct connection states.
- Session persistence works through the `sessions` table.
- A partial unique SQLite index enforces one active session globally.
- Project detail UI supports required mission entry, active-session display, elapsed count-up timer, completion, cancellation, and end-session brain dump.
- Starting a session checks that the selected project folder is still accessible.
- Active-session recovery is shown on app launch with resume, end, and cancel choices.
- Automated M3 tests cover mission validation, complete/cancel transitions, brain dump persistence, active-session uniqueness, project-access failure, and recovery state.
- Snapshot persistence works through the `snapshots` table.
- A deterministic placeholder snapshot is generated from mission and brain dump only.
- Placeholder snapshots always keep `decisions` empty and do not invent unsupported decisions.
- Project detail shows the latest Resume Brief and next action.
- Snapshot detail renders what changed, decisions, open loops, next action, and Resume Brief.
- Retry-safe save/replace behavior keeps one snapshot per session.
- Automated M4 tests cover placeholder generation rules, snapshot persistence, save/replace behavior, latest-snapshot query, and session-completion snapshot creation.
- LM Studio is not required to compile or launch the app.

## Next milestone

Next tasks after merging M4 to `main`:

```text
M5 - Isolated evidence and generation services
```

Use one isolated prompt per branch:

```text
prompts/05a-m5-git-service.md
prompts/05b-m5-file-observation.md
prompts/05c-m5-active-app-observation.md
prompts/05d-m5-lm-studio-generation-client.md
```

Expected branches:

```text
feature/m5a-git-service
feature/m5b-file-observation
feature/m5c-active-app-observation
feature/m5d-lm-studio-generation
```

Do not parallelize M5 branches until M4 has been merged to a clean `main`.

Expected M4 commit message:

```text
feat: add placeholder snapshot vertical slice
```

## Fresh chat startup

In a fresh Codex chat, start by opening this repository root and reading:

- `AGENTS.md`
- `docs/10-current-status.md`
- `docs/05-mvp-roadmap.md`
- `docs/07-macos-build-compile.md`
- the specific M5 prompt being implemented

Then run:

```bash
git status --short
git branch --show-current
./scripts/check.sh
```

Do not start M5 unless M4 has been merged to `main`, `main` is clean, and `./scripts/check.sh` passes.

## M2 completion summary

M2 added local LM Studio configuration only:

- settings repository backed by `app_settings`
- optional Keychain token storage
- `LMStudioSettings` model
- Settings UI and view model
- base URL normalization
- loopback/non-loopback detection and warning
- model listing through `GET /v1/models`
- selected model persistence
- mocked network tests through an injected transport

M2 did not add sessions, observation, snapshot generation, chat completions, or external Swift packages.

Branch:

```text
feature/m2-lm-studio-settings
```

Commit:

```text
6b8dc7e feat: add LM Studio settings and model discovery
```

Validation:

```text
./scripts/check.sh - passed
```

## M3 completion summary

M3 added project session lifecycle only:

- `WorkSession` and `SessionStatus` models
- version 3 sessions migration
- `SessionRepository` backed by SQLite
- one-active-session partial unique index
- required mission validation
- project-folder access check on session start
- project detail start-session form
- active-session screen with elapsed count-up timer
- complete and cancel flows
- end-session brain-dump form with persisted text
- active-session recovery sheet on app launch
- sidebar active-session indicator
- repository and view-model tests for M3 acceptance criteria

M3 must not add observation, events, snapshots, LM Studio generation, Pomodoro intervals, or notifications.

Branch:

```text
feature/m3-session-lifecycle
```

Validation:

```text
./scripts/check.sh - passed
```

## M4 completion summary

M4 added the placeholder snapshot vertical slice only:

- `Snapshot` and `SnapshotDraft` models
- version 4 snapshots migration
- `SnapshotRepository` backed by SQLite
- deterministic `PlaceholderSnapshotGenerator`
- completion flow that saves the brain dump, completes the session, and saves/replaces a placeholder snapshot
- snapshot generation retry state after persistence failure
- latest Resume Brief and next action on project detail
- snapshot detail view
- targeted tests for placeholder generation, persistence, latest query, and session-completion snapshot creation

M4 did not add observation, Git service, file watcher, active-app service, or LM Studio chat completion.

Branch:

```text
feature/m4-placeholder-snapshot
```

Validation:

```text
./scripts/check.sh - passed
```

## M5 scope reminder

M5 owns isolated leaf services only:

- Git service
- file observation
- active-app observation
- LM Studio generation client

Each M5 prompt must stay on its own branch and avoid shared-file collisions.

## Persistent build constraints

Keep these pinned unless explicitly changed by a new accepted decision:

```text
Project: WorkingMemorySnapshot.xcodeproj
Scheme: WorkingMemorySnapshot
Bundle ID: com.broceps.WorkingMemorySnapshot
Minimum macOS target: 14.0
Swift language mode: Swift 5
App Sandbox: off for MVP
SQLite: system SQLite3
LM Studio required for compile: no
```
