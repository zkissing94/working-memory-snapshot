# Working Memory Snapshot — Testing Strategy

## 1. Goal

Test the boundaries most likely to corrupt context, lose user input, violate privacy, or make local inference unreliable.

Prefer small deterministic tests over broad brittle UI automation.

## 2. Test layers

### Unit tests

Cover:

- ISO-8601 encoding and decoding
- SQLite migrations
- repository CRUD and constraints
- project path normalization and persistence
- project-path filtering
- event deduplication
- evidence compaction bounds
- Git output parsing
- LM Studio request construction
- response decoding and validation
- prompt formatting
- loopback URL detection

### Integration tests

Cover:

- repositories against a temporary SQLite database
- project deletion cascade
- one-active-session constraint
- ending a session preserves brain dump
- temporary Git repositories
- mocked URL loading through injected `URLProtocol`
- observation coordinator lifecycle with fake observers
- snapshot generator with fake client and repository

### UI tests

Keep minimal:

- add project flow with an injectable folder-selection boundary
- start and end session
- brain dump survives generation error
- latest Resume Brief is visible
- active-session recovery route

Do not make the entire test suite depend on UI automation.

### Manual tests

Required for OS and local-runtime boundaries:

- real `NSOpenPanel`
- path persistence after relaunch
- App Sandbox access to selected project after the sandbox migration milestone
- `/usr/bin/git` under sandbox after the sandbox migration milestone
- FSEvents in a real project
- `NSWorkspace` activation events
- local focus-block completion notifications and foreground activation
- live LM Studio connection
- local model structured output
- app termination during a session

## 3. Milestone test expectations

### M1

- migration idempotence
- project repository
- duplicate root handling
- path persistence after relaunch
- launch/relaunch manual test

### M2

- settings persistence
- Keychain wrapper
- list-model response
- unauthorized response
- non-loopback warning
- no token in SQLite or logs

### M3

- one active session
- complete and cancel transitions
- brain dump persistence
- launch recovery state

### M4

- placeholder snapshot persistence
- latest snapshot query
- end-to-end manual vertical slice

### M5

- Git parser and temporary repo tests
- path ignore and dedupe tests
- fake active-app notification mapping
- structured-output and retry tests

### M6

- observation starts and stops exactly once
- compacted input is bounded
- user brain dump is preserved verbatim
- snapshot failure does not lose data
- valid result persists transactionally

### M7

- recovery and error-state manual checklist
- keyboard navigation
- VoiceOver labels
- under-60-second dogfood exercise

## 4. LM Studio test policy

Automated tests must not require:

- LM Studio installed
- a model downloaded
- a GPU
- network access

Inject the HTTP transport and stub responses.

Maintain one manual live-server smoke test:

1. Start LM Studio server.
2. Select a downloaded instruct model.
3. Test connection.
4. Complete a session.
5. Generate a snapshot.
6. Confirm JSON fields render.
7. Disconnect server and confirm retry behavior.

## 5. Git test policy

Create temporary repositories inside test directories.

Test:

- non-repository folder
- clean repository
- dirty file present before session
- file changed during session
- new untracked file
- commit created during session
- command failure and timeout
- paths containing spaces

Never rely on the developer's actual repository state.

## 6. File-observation policy

Separate pure path filtering and aggregation from FSEvents.

The FSEvents wrapper gets a small manual/integration test. Most behavior should be testable with synthetic paths and timestamps.

## 7. Validation scripts

`./scripts/check.sh --quick` validates:

- required seed files
- shell syntax
- whitespace errors
- forbidden staged artifacts

`./scripts/check.sh` additionally:

- detects the Xcode workspace/project
- builds the macOS target without signing
- runs tests when a shared scheme is available

Environment overrides:

```text
XCODE_WORKSPACE
XCODE_PROJECT
SCHEME
CONFIGURATION
RUN_TESTS
```

## 8. Product evaluation

After M7, perform at least five real sessions.

For each next-session resume, record manually:

- time to identify the next action
- whether the brief was accurate
- any invented decision
- any missing critical open loop
- whether the user consulted another artifact before resuming

The product passes the first evaluation when the brief is consistently useful and does not create a trust problem through invented memory.

## 9. Daily Rollup coverage

Automated coverage includes migration 9 idempotence, append-only same-day revision retention, exact history selection, source availability, local-day boundaries, snapshot/fallback evidence, fingerprint changes, strict project attribution, word limits, extra keys, 1,500-token request construction, one repair retry, failed-refresh preservation, and view-model states.

Existing snapshot generation tests remain regression coverage for the shared LM Studio request seam. Automated tests continue to use the injected transport and must not require LM Studio, a model, GPU, or network access.

Use `docs/14-daily-rollup-lm-studio-smoke-test.md` for the manual live-model boundary.
