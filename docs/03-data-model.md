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
    bookmark_data BLOB NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE UNIQUE INDEX projects_root_path_unique
ON projects(root_path);
```

`root_path` is for display and diagnostics. Persistent authorization comes from `bookmark_data`.

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

## 7. Snapshots

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

## 8. Application settings

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
snapshot_prompt_version = v1
```

Future keys, not required in the MUI:

```text
lmstudio_janitor_model = ""
janitor_enabled = false
```

The LM Studio API token is stored in Keychain under a stable service and account identifier.

## 9. Domain models

Suggested shapes:

```swift
struct Project: Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var rootPath: String
    var bookmarkData: Data
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

## 10. Repository contracts

### ProjectRepository

- create project
- list projects
- get project
- update bookmark
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

## 11. Invariants

- A project can exist without sessions.
- A session can exist without a snapshot.
- A completed session may be retried for snapshot generation.
- A cancelled session does not generate a snapshot.
- A brain dump survives generation failure.
- Only one active session exists.
- Events are accepted only for the active session.
- Snapshot arrays may be empty.
- Project deletion cascades to sessions, events, and snapshots after confirmation.
