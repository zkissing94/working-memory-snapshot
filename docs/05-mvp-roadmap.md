# Working Memory Snapshot — MVP Roadmap

## Sequencing principle

Build one end-to-end vertical slice before parallelizing leaf services.

```text
M0 repository seed
→ M1 app shell + build foundation + project persistence
→ M2 LM Studio settings
→ M3 session lifecycle
→ M4 placeholder snapshot vertical slice
→ M5 isolated evidence and generation services
→ M6 real snapshot integration
→ M7 resume and recovery polish
→ M8 session timeline and Pomodoro capture redesign
```

## M0 — Repository seed

### Goal

Create a clean Git baseline with product context and Codex operating rules.

### Deliverables

- all seed documents
- `AGENTS.md`
- repository skill
- `.gitignore`
- hooks and validation scripts
- initial documentation commit

### Exit criteria

- repository is initialized on `main`
- hooks are installed
- `./scripts/check.sh --quick` passes
- seed files are committed
- worktree is clean

## M1 — App shell, build foundation, and project persistence

### Goal

Launch a native SwiftUI macOS app with a reproducible build path and persisted user-selected projects.

### Deliverables

- Xcode macOS app scaffold
- shared `WorkingMemorySnapshot` scheme
- `.xcconfig` build configuration
- explicit `Info.plist`
- `scripts/check.sh`
- `scripts/doctor.sh`
- `NavigationSplitView`
- SQLite database and migration runner
- project repository
- `NSOpenPanel` project selection
- path-based project persistence with App Sandbox off for MVP
- project list and empty state
- project persistence across launches
- unit tests for migrations and repository behavior

### Branch

```text
feature/m1-app-shell-build-sqlite
```

### Exit criteria

- app builds
- user can select a folder
- project appears
- project remains after relaunch
- `./scripts/check.sh` passes
- no session, observation, or model code exists yet

## M2 — LM Studio settings

### Goal

Configure and verify the local inference server without generating snapshots.

### Deliverables

- settings repository
- Keychain token store
- Settings UI
- base URL validation
- model listing through `GET /v1/models`
- model selection
- non-loopback warning
- mocked network tests

### Branch

```text
feature/m2-lm-studio-settings
```

### Exit criteria

- settings persist
- token does not appear in SQLite
- connection states are distinguishable
- models can be listed from a running local server
- app builds and tests pass

## M3 — Session lifecycle

### Goal

Create and recover a project-based session.

### Deliverables

- session repository
- one-active-session invariant
- mission form
- active-session view
- elapsed timer
- end and cancel flows
- brain dump persistence
- active-session recovery on relaunch

### Branch

```text
feature/m3-session-lifecycle
```

### Exit criteria

- session can start, end, and cancel
- a second active session is rejected
- brain dump persists
- relaunch offers recovery
- no observation or real model generation yet

## M4 — Placeholder snapshot vertical slice

### Goal

Prove the entire user journey before adding ambient evidence or model behavior.

### Deliverables

- snapshot repository
- deterministic placeholder snapshot based on mission and brain dump
- snapshot view
- latest Resume Brief on project detail
- start a new session from project detail

### Branch

```text
feature/m4-placeholder-snapshot
```

### Exit criteria

This works end to end:

```text
project → mission → session → brain dump → placeholder snapshot → relaunch → resume
```

Do not parallelize before M4 is merged.

## M5 — Isolated leaf services

After M4 is on a clean `main`, these may run in separate Codex worktrees based on the same commit.

### M5a — GitService

Branch:

```text
feature/m5a-git-service
```

Owns:

- `ProcessRunner`
- Git repository detection
- bounded Git evidence
- tests using temporary repositories

### M5b — File observation

Branch:

```text
feature/m5b-file-observation
```

Owns:

- path filtering
- FSEvents wrapper
- session-scoped changed-path aggregation
- tests for filtering and compaction

### M5c — Active-app observation

Branch:

```text
feature/m5c-active-app-observation
```

Owns:

- `NSWorkspace` activation observation
- transition deduplication
- testable event mapping

### M5d — LM Studio generation client

Branch:

```text
feature/m5d-lm-studio-generation
```

Owns:

- structured completion request
- response models
- JSON validation
- repair retry
- mocked tests

### Parallel safety

Each task must declare its allowed files. Shared models may be changed only through a tiny pre-agreed interface commit or during serial integration.

## M6 — Real snapshot integration

### Goal

Replace placeholder generation with grounded local synthesis.

### Deliverables

- `ObservationCoordinator`
- `EvidenceCompactor`
- `PromptBuilder`
- `SnapshotGenerator`
- wiring of M5 services
- model generation UI state
- retry behavior
- persistence of real snapshots

### Branch

```text
feature/m6-real-snapshot-integration
```

### Exit criteria

- observation runs only during active sessions
- model input is bounded
- valid snapshots persist
- model failure preserves session and brain dump
- no unsupported decisions are inserted by deterministic fallback
- full check passes

## M7 — Resume and recovery polish

### Goal

Make the killer demo obvious and robust.

### Deliverables

- latest Resume Brief immediately visible
- next action emphasized
- session recovery polish
- lost-project-access recovery
- empty and error states
- accessibility pass
- manual dogfood checklist

### Branch

```text
feature/m7-resume-recovery-polish
```

### MVP exit criteria

A dogfood user can reopen the app and identify the correct next action in under 60 seconds.

## M8 — Session timeline and Pomodoro capture redesign

Post-MVP only, after M7 dogfood and merge.

### Goal

Make sessions easier to scan and resume by adding a project dashboard, historical session detail, and Pomodoro blocks as lightweight capture points inside a session.

### Deliverables

- two-column `NavigationSplitView` structure with a persistent project sidebar and single workspace
- card-like sidebar project rows with active project state and metadata
- project workspace with previous sessions grouped by date, latest memory summary, and route-specific session/detail states
- active-session block surface with 20-minute countdown, pause/resume, complete block, next block, break, and end-session actions
- `pomodoro_blocks` and `work_increments` tables
- block and increment repositories
- active-block recovery for existing active sessions
- snapshot evidence that includes block summaries and manual note/decision/blocker increments above passive evidence
- historical session detail with snapshot sections, block timeline, and read-only observed context from existing Git/file/app events

### Branch

```text
feature/m8-session-timeline-blocks
```

### Exit criteria

- starting a session creates Block 1 with a 20-minute default duration
- one active or paused block exists per session
- completing a block does not end the session
- break state leaves the session active with no active block
- ending or cancelling a session interrupts any open block
- snapshots include user-entered block capture points without adding message/transcript observation
- project deletion cascades sessions, events, blocks, increments, and snapshots
- full check passes

## M9 — Optional evidence-janitor model

Post-MVP only.

Add the small model if measured evidence supports it. Define an evaluation comparing:

- deterministic compaction
- small-model compaction
- latency
- snapshot correctness
- omitted critical evidence
- invented conclusions

Do not add it because the architecture diagram looks more sophisticated.

## Merge cadence

For every milestone:

1. branch from clean `main`
2. implement scoped work
3. run checks
4. review diff
5. create atomic commit(s)
6. review acceptance criteria
7. merge only on explicit instruction
8. begin the next milestone from updated `main`
