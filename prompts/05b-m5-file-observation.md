$milestone-execution

Implement M5b only: project file observation as an isolated leaf task.

Run this in a Codex worktree based on the clean M4 `main` commit.

Required reading:
- AGENTS.md
- docs/01-system-architecture.md
- docs/05-mvp-roadmap.md
- docs/07-testing-strategy.md
- docs/09-risk-register.md

Branch:
`feature/m5b-file-observation`

Allowed areas:
- `WorkingMemorySnapshot/Observation/FileObservationService.swift`
- pure path-filter and path-aggregation types
- corresponding test files
- decision log only when required

Do not modify:
- views
- database schema
- repositories
- GitService
- LM Studio code
- global navigation

Scope:
- FSEvents wrapper scoped to the selected project
- injectable callback/output boundary
- relative-path conversion
- ignored directory segments from architecture doc
- collapse repeated changes by path
- first/last timestamp and count
- bounded buffering
- clean stop and cancellation
- pure unit tests for filtering and aggregation
- manual FSEvents smoke instructions

Acceptance criteria:
- ignored paths never appear
- paths outside project root are rejected
- repeated changes compact correctly
- observer stops without emitting after session end
- tests and full check pass

Commit:
`feat: observe session-scoped project file changes`
