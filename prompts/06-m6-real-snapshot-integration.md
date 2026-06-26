$milestone-execution

Implement M6 only: real observation and snapshot integration.

This is a serial integration task. Begin after reviewed M5 branches are merged into a clean `main`.

Required reading:
- AGENTS.md
- all product and architecture docs
- docs/04-local-ai-spec.md
- docs/05-mvp-roadmap.md
- docs/07-testing-strategy.md
- docs/09-risk-register.md

Branch:
`feature/m6-real-snapshot-integration`

Scope:
- events migration and repository
- ObservationCoordinator
- wire Git, file, and active-app services to active sessions
- EvidenceCompactor with deterministic bounds
- PromptBuilder and prompt version `v1`
- SnapshotGenerator orchestration
- replace placeholder generator with LM Studio generation
- generation loading, retry, and errors
- preserve session and brain dump on failure
- integration tests with fake observers/client/repositories
- update docs only for deliberate interface decisions

Do not implement:
- small-model janitor
- raw file-content reading
- deep tool integrations
- screenshots
- transcript scraping
- cloud behavior

Acceptance criteria:
- no events are recorded without an active session
- observers start and stop once
- brain dump is preserved verbatim
- model input is bounded and excludes forbidden data
- structured result persists
- invalid result does not replace valid data
- non-Git projects work
- generation failure is retryable
- tests and full check pass

Commit:
`feat: generate grounded working memory snapshots`
