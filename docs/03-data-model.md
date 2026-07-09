# Working Memory Snapshot — Data Model

## 1. Principles

- SQLite is the local source of truth.
- IDs are UUID strings.
- Timestamps are UTC ISO-8601 strings.
- Foreign keys are enabled.
- Schema changes use numbered migrations.
- Sensitive authentication material is not stored in SQLite.
- Generic events preserve flexibility without tool-specific tables.

## 2. Database pragmas

Apply on every connection as appropriate:

```sql
PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
```

## 3. Migration table

```sql
CREATE TABLE IF NOT EXISTS schema_migrations (
    version INTEGER PRIMARY KEY,
    applied_at TEXT NOT NULL
);
```

## 4. Projects

```sql
CREATE TABLE projects (
    id TEXT PRIMARY KEY NOT NULL,
    name TEXT NOT NULL,
    root_path TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE UNIQUE INDEX projects_root_path_unique
ON projects(root_path);
```

`root_path` is the MVP project boundary. Security-scoped bookmark data is deferred until the App Sandbox migration milestone.

## 5. Sessions

```sql
CREATE TABLE sessions (
    id TEXT PRIMARY KEY NOT NULL,
    project_id TEXT NOT NULL,
    mission TEXT NOT NULL,
    brain_dump TEXT,
    started_at TEXT NOT NULL,
    ended_at TEXT,
    status TEXT NOT NULL CHECK (
        status IN ('active', 'completed', 'cancelled')
    ),
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    FOREIGN KEY(project_id) REFERENCES projects(id) ON DELETE CASCADE
);

CREATE INDEX sessions_project_started_index
ON sessions(project_id, started_at DESC);

CREATE UNIQUE INDEX sessions_single_active_index
ON sessions(status)
WHERE status = 'active';
```

The partial unique index enforces one active session globally.

## 6. Events

```sql
CREATE TABLE events (
    id TEXT PRIMARY KEY NOT NULL,
    session_id TEXT NOT NULL,
    occurred_at TEXT NOT NULL,
    source TEXT NOT NULL CHECK (
        source IN ('system', 'user', 'file', 'git', 'active_app')
    ),
    kind TEXT NOT NULL,
    title TEXT NOT NULL,
    body TEXT,
    payload_json TEXT,
    created_at TEXT NOT NULL,
    FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE
);

CREATE INDEX events_session_time_index
ON events(session_id, occurred_at ASC);

CREATE INDEX events_session_source_kind_index
ON events(session_id, source, kind);
```

### Initial event kinds

```text
session_started
session_ended
session_cancelled
brain_dump
file_changed
git_initial_state
git_final_summary
app_activated
```

Adding a kind does not require a schema migration.

## 7. Pomodoro blocks and work increments

Pomodoro blocks are lightweight capture points inside a session. They do not replace sessions, and they do not duplicate passive evidence.

```sql
CREATE TABLE pomodoro_blocks (
    id TEXT PRIMARY KEY NOT NULL,
    session_id TEXT NOT NULL,
    block_index INTEGER NOT NULL,
    planned_duration_seconds INTEGER NOT NULL,
    intention TEXT,
    summary TEXT,
    status TEXT NOT NULL CHECK (
        status IN ('active', 'paused', 'completed', 'interrupted')
    ),
    started_at TEXT NOT NULL,
    paused_at TEXT,
    accumulated_pause_seconds INTEGER NOT NULL,
    ended_at TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE
);

CREATE UNIQUE INDEX pomodoro_blocks_session_index_unique
ON pomodoro_blocks(session_id, block_index);

CREATE UNIQUE INDEX pomodoro_blocks_one_open_per_session
ON pomodoro_blocks(session_id)
WHERE status IN ('active', 'paused');

CREATE INDEX pomodoro_blocks_session_started_index
ON pomodoro_blocks(session_id, started_at ASC);
```

`planned_duration_seconds` defaults to 1200 for the 20-minute capture block. `accumulated_pause_seconds` is used to preserve remaining time across app reloads.

```sql
CREATE TABLE work_increments (
    id TEXT PRIMARY KEY NOT NULL,
    block_id TEXT NOT NULL,
    occurred_at TEXT NOT NULL,
    kind TEXT NOT NULL CHECK (
        kind IN ('note', 'decision', 'blocker')
    ),
    title TEXT NOT NULL,
    detail TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    FOREIGN KEY(block_id) REFERENCES pomodoro_blocks(id) ON DELETE CASCADE
);

CREATE INDEX work_increments_block_time_index
ON work_increments(block_id, occurred_at ASC);
```

Work increments are manual, user-entered capture. Git/file/app observations remain in the generic `events` table and are rendered as read-only observed context.

Block completion alerts do not add persistence. The deadline is derived from `started_at`, `paused_at`, `accumulated_pause_seconds`, `planned_duration_seconds`, `status`, and `ended_at`. Reaching zero does not write to SQLite; the existing `completeBlock(summary:)` repository path persists completion only after the user confirms.

## 8. Snapshots

```sql
CREATE TABLE snapshots (
    id TEXT PRIMARY KEY NOT NULL,
    session_id TEXT NOT NULL,
    what_changed TEXT NOT NULL,
    decisions_json TEXT NOT NULL,
    open_loops_json TEXT NOT NULL,
    next_action TEXT NOT NULL,
    resume_brief TEXT NOT NULL,
    generator_model TEXT,
    prompt_version TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE
);

CREATE UNIQUE INDEX snapshots_session_unique
ON snapshots(session_id);
```

`decisions_json` and `open_loops_json` encode arrays of strings. Decode errors are treated as data corruption, not silently replaced.

## 9. Application settings

```sql
CREATE TABLE app_settings (
    key TEXT PRIMARY KEY NOT NULL,
    value TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
```

Initial keys:

```text
lmstudio_base_url = http://localhost:1234/v1
lmstudio_synthesizer_model = ""
```

Future keys, not required in the MUI:

```text
lmstudio_janitor_model = ""
janitor_enabled = false
```

The LM Studio API token is stored in Keychain under a stable service and account identifier.

Migration 7 removes the legacy `snapshot_prompt_version` app setting. Persisted `snapshots.prompt_version` fields remain unchanged; new generation uses the code-owned `PromptBuilder.promptVersion`.

## 10. Domain models

Suggested shapes:

```swift
struct Project: Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var rootPath: String
    var createdAt: Date
    var updatedAt: Date
}
```

```swift
enum SessionStatus: String, Codable, Sendable {
    case active
    case completed
    case cancelled
}

struct WorkSession: Identifiable, Equatable, Sendable {
    let id: UUID
    let projectID: UUID
    var mission: String
    var brainDump: String?
    var startedAt: Date
    var endedAt: Date?
    var status: SessionStatus
    var createdAt: Date
    var updatedAt: Date
}
```

```swift
enum PomodoroBlockStatus: String, Codable, Sendable {
    case active
    case paused
    case completed
    case interrupted
}

struct PomodoroBlock: Identifiable, Equatable, Sendable {
    let id: UUID
    let sessionID: UUID
    var blockIndex: Int
    var plannedDurationSeconds: Int
    var intention: String?
    var summary: String?
    var status: PomodoroBlockStatus
    var startedAt: Date
    var pausedAt: Date?
    var accumulatedPauseSeconds: Int
    var endedAt: Date?
    var createdAt: Date
    var updatedAt: Date
}
```

```swift
enum WorkIncrementKind: String, Codable, Sendable {
    case note
    case decision
    case blocker
}

struct WorkIncrement: Identifiable, Equatable, Sendable {
    let id: UUID
    let blockID: UUID
    var occurredAt: Date
    var kind: WorkIncrementKind
    var title: String
    var detail: String?
    var createdAt: Date
    var updatedAt: Date
}
```

```swift
enum EventSource: String, Codable, Sendable {
    case system
    case user
    case file
    case git
    case activeApp = "active_app"
}

struct SessionEvent: Identifiable, Equatable, Sendable {
    let id: UUID
    let sessionID: UUID
    let occurredAt: Date
    let source: EventSource
    let kind: String
    let title: String
    let body: String?
    let payloadJSON: String?
    let createdAt: Date
}
```

```swift
struct Snapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    let sessionID: UUID
    var whatChanged: String
    var decisions: [String]
    var openLoops: [String]
    var nextAction: String
    var resumeBrief: String
    var generatorModel: String?
    var promptVersion: String
    var createdAt: Date
    var updatedAt: Date
}
```

## 11. Repository contracts

### ProjectRepository

- create project
- list projects
- get project
- delete project

### SessionRepository

- create active session
- get active session
- complete session
- cancel session
- list sessions for project
- get latest completed session

### EventRepository

- insert event
- insert events in a transaction
- list events for session
- count events by source or kind
- list distinct active apps
- list changed file paths

### PomodoroBlockRepository

- create next block for active session
- ensure the first block for legacy active sessions
- get open block for session
- list blocks for session
- pause block
- resume block
- complete block
- interrupt open block before session end or cancellation

### WorkIncrementRepository

- add manual increment to an active or paused block in an active session
- list increments for block
- list increments for session

### SnapshotRepository

- save or replace snapshot for session
- get snapshot for session
- get latest snapshot for project
- list snapshots for project

### SettingsRepository

- get and set values
- load LM Studio settings
- save LM Studio settings without token

### KeychainStore

- load optional token
- save optional token
- delete token

## 12. Invariants

- A project can exist without sessions.
- A session can exist without a snapshot.
- A completed session may be retried for snapshot generation.
- A cancelled session does not generate a snapshot.
- A brain dump survives generation failure.
- Only one active session exists.
- A session may contain zero or more Pomodoro blocks.
- Only one active or paused Pomodoro block exists per session.
- Starting a new session creates Block 1 with a 20-minute default duration.
- Legacy active sessions without blocks are recovered by creating Block 1.
- Completing a block does not complete the session.
- Ending or cancelling a session interrupts any active or paused block first.
- Work increments are manual notes, decisions, or blockers attached to blocks.
- Events are accepted only for the active session.
- Passive Git/file/app evidence remains in generic events, not in block-specific or tool-specific tables.
- Snapshot arrays may be empty.
- Project deletion cascades to sessions, events, blocks, increments, and snapshots after confirmation.
