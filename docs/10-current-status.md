# Working Memory Snapshot - Current Status

## Where the project is

Current handoff branch:

```text
9b-two-column-app-structure
```

Current focus:

```text
M8/M9 app structure implementation - two-column workspace across mapped states
```

Baseline:

```text
main is at the completed M8 session timeline and Pomodoro capture implementation.
```

Completed milestones:

- M0 - Repository seed and Codex workflow
- M1 - App shell, build foundation, and project persistence
- M2 - LM Studio settings and model discovery
- M3 - Session lifecycle
- M4 - Placeholder snapshot vertical slice
- M5 - Isolated evidence and generation services
- M6 - Real snapshot integration
- M7 - Resume and recovery polish
- M8 - Session timeline and Pomodoro capture redesign

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
- Generic session events persist through the `events` table.
- Observation starts only for active sessions and stops at completion or cancellation.
- File observation records bounded project-relative changed paths.
- Git evidence captures initial state and final bounded summaries when the project is in a Git repository.
- Active-app observation records application transitions only, not window content.
- Evidence compaction deterministically bounds passive evidence while preserving the brain dump verbatim.
- `PromptBuilder` creates prompt version `v1` with the local AI prompt-injection boundary.
- `SnapshotGenerator` calls LM Studio structured chat completions and persists only valid snapshots.
- Generation failure preserves the completed session and brain dump and exposes retry.
- Non-Git projects remain valid and produce non-Git evidence notes.
- Project detail shows the latest Resume Brief and next action.
- Snapshot detail renders what changed, decisions, open loops, next action, and Resume Brief.
- Retry-safe save/replace behavior keeps one snapshot per session.
- Automated M6 tests cover event persistence, observation lifecycle, compaction bounds, prompt formatting, generator persistence, and invalid-result retry safety.
- Project detail places the latest Resume Brief and next action before project metadata when a snapshot exists.
- Lost project-folder access is visible from project detail and can be restored with the native folder picker.
- Active-session recovery distinguishes accessible and inaccessible project folders; Resume Session is blocked until access is restored.
- Snapshot generation failure states make clear that the session and brain dump are saved and retryable.
- Settings connection states include concrete recovery suggestions for LM Studio failures and empty model lists.
- Primary controls have accessibility labels or hints, and app-level commands support Command-N and Command-Comma.
- The five-session M7 manual dogfood checklist is documented in `docs/11-m7-dogfood-checklist.md`.
- Automated M7 tests cover project path restoration, duplicate restore rejection, visible access state, recovery blocking for missing folders, and settings recovery copy.
- SQLite migration version 6 adds `pomodoro_blocks` and `work_increments`.
- `PomodoroBlockRepository` and `WorkIncrementRepository` manage block lifecycle and manual note/decision/blocker capture.
- Starting a session creates Block 1 with a 20-minute default duration.
- Legacy active sessions without blocks recover by creating Block 1.
- Only one active or paused block can exist per session.
- Completing a block leaves the session active and allows a next block.
- Taking a break leaves the session active with no open block.
- Ending or cancelling a session interrupts any active or paused block before the existing brain-dump/cancel flow continues.
- The main UI now uses a two-column structure: persistent project sidebar and single workspace.
- The workspace route maps empty library, project dashboard, start session, active/paused/between-block session states, end-session brain dump, snapshot generation failure, snapshot detail, historical session detail, recovery sheets, project access loss, and settings into the right-hand column.
- The project dashboard shows project metrics, latest memory, start-session action, and previous sessions grouped by date.
- Historical session detail shows mission, timing, snapshot sections, block timeline, and observed context from existing Git/file/app events.
- Snapshot evidence includes user-entered block summaries and manual increments below the brain dump and above passive evidence.
- Message, transcript, clipboard, browser-history, screenshot, and keystroke observation remain excluded.
- Automated M8 tests cover migration v6, block/increment repositories, session view-model block flow, snapshot prompt inclusion, compaction, and project-deletion cascades.
- LM Studio is not required to compile or launch the app.

## Next milestone

Next task after merging the two-column app structure:

```text
Manual dogfood review of the 16 mapped app states
```

Expected prompt:

```text
Launch the app and manually dogfood the two-column workspace against docs/mockups/app-state-mockups.html.
```

Optional post-MVP milestone:

```text
M9 - Optional evidence-janitor model
```

Expected commit message:

```text
feat: implement two-column app structure
```

## Fresh chat startup

In a fresh Codex chat, start by opening this repository root and reading:

- `AGENTS.md`
- `docs/10-current-status.md`
- `docs/05-mvp-roadmap.md`
- `docs/07-macos-build-compile.md`
- the specific milestone prompt being implemented

Then run:

```bash
git status --short
git branch --show-current
./scripts/check.sh
```

Do not start post-MVP M9 unless M8 has been merged, the M8 UI flow has been dogfooded, the worktree is clean, and `./scripts/check.sh` passes.

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

## M5 completion summary

M5 completed isolated leaf services:

- Git service
- file observation
- active-app observation
- LM Studio generation client

M6 integrated those branches serially into the app flow.

## M6 completion summary

M6 replaced placeholder generation with grounded local synthesis:

- version 5 events migration and `EventRepository`
- `ObservationCoordinator` for session-scoped file, Git, and active-app evidence
- deterministic `EvidenceCompactor`
- `PromptBuilder` prompt version `v1`
- `SnapshotGenerator` orchestration through LM Studio structured output
- active-session observed summary UI
- generation progress, failure, and retry behavior
- tests for event persistence, observation lifecycle, compaction bounds, prompt formatting, generation persistence, and invalid-result safety

Branch:

```text
feature/m6-real-snapshot-integration
```

Validation:

```text
./scripts/check.sh - passed
```

## M7 completion summary

M7 polished the core resume and recovery loop:

- latest Resume Brief and Start here action appear before project metadata
- project detail detects missing selected folders and offers Choose Folder Again
- selected project root paths can be restored without schema changes
- active-session recovery blocks Resume Session when the folder is inaccessible and offers restoration
- snapshot generation failures show saved-session context and retry
- LM Studio settings errors include actionable recovery suggestions
- primary controls gained accessibility labels or hints
- Command-N starts a session for the selected project or adds a project when no project is selected
- Command-Comma opens Settings
- five-session manual dogfood checklist added

Branch:

```text
feature/m7-resume-recovery-polish
```

Validation:

```text
./scripts/check.sh - passed
```

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
