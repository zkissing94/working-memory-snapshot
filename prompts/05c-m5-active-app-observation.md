$milestone-execution

Implement M5c only: active-application observation as an isolated leaf task.

Run this in a Codex worktree based on the clean M4 `main` commit.

Required reading:
- AGENTS.md
- docs/01-system-architecture.md
- docs/05-mvp-roadmap.md
- docs/07-testing-strategy.md

Branch:
`feature/m5c-active-app-observation`

Allowed areas:
- `WorkingMemorySnapshot/Observation/ActiveAppObservationService.swift`
- focused active-app models
- corresponding test files

Do not modify:
- views
- database schema
- repositories
- GitService
- file observation
- LM Studio code

Scope:
- observe `NSWorkspace` application activation notifications
- record initial frontmost application
- map display name and bundle identifier
- discard consecutive duplicates
- expose start/stop lifecycle
- do not use Accessibility APIs
- do not capture window titles
- test event mapping with an injectable notification/source boundary

Acceptance criteria:
- initial app is emitted once
- transitions emit once
- consecutive duplicates do not emit
- stop removes observers
- no content beyond app identity is captured
- tests and full check pass

Commit:
`feat: observe active application transitions`
