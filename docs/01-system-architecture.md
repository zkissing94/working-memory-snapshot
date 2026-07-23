# Working Memory Snapshot — System Architecture

## 1. Architecture goal

Build the smallest native macOS system that reliably performs:

```text
capture boundary → collect evidence → compact evidence → synthesize snapshot → restore context
```

Optimize for clarity, privacy, testability, and reversible decisions. Do not build a platform before the core loop is validated.

## 2. Platform decisions

- Swift
- SwiftUI
- macOS 14.0+
- AppKit bridges where required
- Local SQLite through the system SQLite library
- Foundation `URLSession` for LM Studio
- Keychain for an optional LM Studio token
- No cloud services
- No production third-party dependencies in the first vertical slice

A dependency may be added only when it removes meaningful risk or boilerplate and is recorded in the decision log.

## 3. High-level components

```text
SwiftUI Views
      ↓
@MainActor ViewModels
      ↓
Application Services
      ↓
Repositories / Database actor
      ↓
SQLite in Application Support

Observation sources
      ↓
ObservationCoordinator
      ↓
Generic Event records
      ↓
EvidenceCompactor
      ↓
PromptBuilder
      ↓
LMStudioClient
      ↓
SnapshotGenerator
      ↓
SnapshotRepository
```

## 4. Suggested source layout

```text
WorkingMemorySnapshot/
  App/
    WorkingMemorySnapshotApp.swift
    AppEnvironment.swift
    AppRoute.swift

  Models/
    Project.swift
    WorkSession.swift
    SessionEvent.swift
    Snapshot.swift
    LMStudioSettings.swift

  Persistence/
    Database.swift
    DatabaseMigrator.swift
    ProjectRepository.swift
    SessionRepository.swift
    EventRepository.swift
    SnapshotRepository.swift
    SettingsRepository.swift

  ProjectAccess/
    ProjectAccessService.swift
    SecurityScopedResource.swift

  Observation/
    ObservationCoordinator.swift
    FileObservationService.swift
    GitService.swift
    ActiveAppObservationService.swift
    EvidenceCompactor.swift

  LocalAI/
    LMStudioClient.swift
    PromptBuilder.swift
    SnapshotGenerator.swift
    SnapshotSchema.swift

  Security/
    KeychainStore.swift

  Features/
    Projects/
    ProjectDetail/
    Session/
    Snapshot/
    Settings/

  Utilities/
    AppError.swift
    ISO8601DateCoding.swift
    ProcessRunner.swift
```

Feature folders may contain their view, view model, and small feature-specific components. Shared services remain in the top-level domains.

## 5. Concurrency model

- View models are `@MainActor`.
- Database access is serialized through a `Database` actor.
- Observation coordination is owned by an actor or another single explicit serial executor.
- File, Git, and network work never blocks the main actor.
- Services expose `async` APIs when they perform I/O.
- Cancellation propagates when a session ends or a screen disappears.
- Avoid detached tasks unless the lifetime is deliberate and documented.

## 6. Persistence

### Database location

Place the database in:

```text
~/Library/Application Support/WorkingMemorySnapshot/working-memory.sqlite3
```

Create the directory with appropriate user-only access.

Enable:

```sql
PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;
```

All schema changes go through numbered migrations.

### Repository boundary

Views and view models do not issue SQL. Repositories translate between SQLite rows and domain models.

### Transaction boundaries

Use transactions for:

- project creation plus path persistence
- ending a session plus saving the brain dump and end event
- replacing or saving a generated snapshot
- deleting a project and cascading related local records

## 7. Project-folder access

MVP project creation flow:

1. Present `NSOpenPanel` configured for a single directory.
2. Receive the system-provided URL.
3. Persist the display path locally.
4. Use the path only for the selected project boundary.

The MVP runs with App Sandbox off to avoid security-scoped bookmark and entitlement complexity before the core product loop is proven.

## 8. App Sandbox and entitlements

App Sandbox migration is deferred to a dedicated milestone.

When sandboxing is enabled later, add:

- user-selected file read/write entitlement
- outgoing network client entitlement for LM Studio
- app-scoped security-scoped bookmarks
- stale bookmark refresh
- Git subprocess validation while security-scoped project access is active

Do not enable App Sandbox during MVP feature work unless explicitly requested.

## 9. Session lifecycle

Only one active session is allowed in v0.

```text
idle
→ starting
→ active
→ ending
→ generatingSnapshot
→ completed
```

Cancellation is distinct from completion.

At session start:

- validate project access
- create the active session
- create `session_started` event
- start observation
- capture initial Git evidence when applicable

At session end:

- stop accepting new observer callbacks
- capture final evidence
- save the brain dump
- create `brain_dump` and `session_ended` events
- mark the session complete
- generate a snapshot asynchronously
- preserve all saved data if generation fails

On app launch, detect an active session and offer:

- resume observation
- end the session
- cancel the session

Do not create a second active session.

## 10. Generic event envelope

Every observation becomes a generic event:

```text
id
session_id
occurred_at
source
kind
title
body
payload_json
```

Sources:

- `system`
- `user`
- `file`
- `git`
- `active_app`

Kinds are stable string values, not tool-specific schemas.

Examples:

```text
source=file, kind=file_changed
source=git, kind=git_initial_state
source=git, kind=git_final_summary
source=active_app, kind=app_activated
source=user, kind=brain_dump
```

Raw evidence should remain compact. Do not store screen content or full project files.

## 11. File observation

Preferred implementation: macOS FSEvents scoped to the resolved project URL.

Requirements:

- recursive project-tree coverage
- ignore generated and noisy directories
- record relative paths only
- deduplicate repeated path changes
- bound in-memory buffering
- stop immediately when the session ends
- no observation outside the project root

Initial ignored segments:

```text
.git
node_modules
.next
dist
build
DerivedData
.venv
venv
.swiftpm
.build
```

Path filtering must be testable independently from FSEvents.

A polling fallback may be used only if FSEvents blocks the milestone. Record the fallback and its performance limitations.

## 12. Git observation

Use `Process` with `/usr/bin/git` and an argument array. Do not compose shell strings.

Capture:

- repository detection
- branch name when available
- HEAD at session start
- initial porcelain status
- final porcelain status
- changed paths touched during the session
- bounded diff stat
- commits created after the starting HEAD, when applicable

Do not send a full unbounded diff to the model.

Pre-existing working-tree changes must be distinguishable from paths observed during the session. The model should not assume every final dirty file was changed during this session.

Non-Git folders are valid projects and must not produce an error state.

## 13. Active-app observation

Use `NSWorkspace` application-activation notifications rather than polling continuously.

Record:

- the app active at session start
- a new event when the frontmost application changes
- application display name
- bundle identifier when available

Do not record:

- window title
- document name
- keystrokes
- accessibility content
- screenshots

Consecutive duplicates are discarded.

## 14. Evidence compaction

The MUI uses deterministic rules:

- collapse file changes by relative path
- preserve first and last observed timestamps
- count repeated changes
- list unique active apps in order of first appearance
- checkpoint file activity at focus-block state boundaries without stopping FSEvents
- group checkpointed file and app evidence by focus block or between-block window
- keep older events without window metadata in an explicit session-wide fallback
- collapse Git evidence into a bounded summary
- remove duplicate system events
- hard-limit event count and text size sent to the model
- preserve the brain dump verbatim

The compactor returns an explicit typed input for `PromptBuilder`.

The future small model may replace or augment this component after evidence demonstrates a need.

## 15. LM Studio boundary

`LMStudioClient` owns:

- base URL validation
- optional bearer token attachment
- `GET /v1/models`
- structured `POST /v1/chat/completions`
- timeouts
- HTTP error mapping
- response decoding

`PromptBuilder` owns:

- system instructions
- evidence formatting
- JSON schema
- prompt-injection boundary language

`SnapshotGenerator` owns orchestration, validation, mapping, and persistence.

No view should construct HTTP payloads or prompts.

## 16. Security boundaries

- Default LM Studio URL is loopback.
- A non-loopback URL requires a visible warning.
- Optional token is stored in Keychain.
- Observed strings are treated as data, never instructions.
- Model output is not executable.
- The app does not expose model tools.
- The app does not execute commands proposed by the model.
- Process arguments are passed as arrays.
- Relative project paths are validated to remain under the selected root.

## 17. Error model

Use a small typed `AppError` surface with user-facing descriptions for:

- database initialization or migration
- inaccessible or moved project folder
- inaccessible project folder
- Git unavailable or command failure
- LM Studio unreachable
- no model selected
- authentication rejected
- unsupported structured output
- invalid model JSON
- snapshot persistence failure

Internal diagnostics may include underlying errors, but UI copy should tell the user what action is possible.

## 18. Logging

Use `Logger` / `OSLog` with privacy annotations.

Never log:

- brain dump contents
- API tokens
- full model prompts
- full model responses
- absolute private paths in release logs

Log categories may include:

- database
- projectAccess
- observation
- git
- localAI
- lifecycle

## 19. Architectural non-goals

Do not add:

- plugin architecture
- graph database
- event sourcing framework
- background launch agent
- menu-bar extra
- cloud sync
- distributed model service
- deep editor integrations
- global hotkeys
- cross-platform abstraction

These decisions may be revisited only after the core resume loop is validated.

## 20. Global Daily Rollup

Daily Rollup is a durable derived artifact across completed sessions, not a new observation source or backend.

```text
completed sessions for local day
      ↓
DailyRollupSourceLoader
      ↓
snapshot-first bounded evidence with capture-point fallback
      ↓
DailyRollupPromptBuilder
      ↓
LMStudioClient structured completion
      ↓
DailyRollupGenerator
      ↓
DailyRollupRepository / SQLite
```

The source fingerprint is deterministic over eligible session and snapshot update identities. Every successful generation appends a validated revision and the latest revision remains the default for its local day. A failed refresh appends nothing, so all previous runs remain readable. Source metadata is retained per revision; drill-down availability is resolved against current sessions.
