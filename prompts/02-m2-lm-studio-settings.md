$milestone-execution

Implement M2 only: LM Studio settings and connection testing.

Required reading:
- AGENTS.md
- docs/10-current-status.md
- docs/01-system-architecture.md
- docs/02-ui-spec.md
- docs/03-data-model.md
- docs/04-local-ai-spec.md
- docs/05-mvp-roadmap.md
- docs/07-macos-build-compile.md
- docs/07-testing-strategy.md

Branch:
`feature/m2-lm-studio-settings`

Scope:
- app_settings migration and repository
- KeychainStore for optional API token
- LMStudioSettings domain model
- Settings view and view model
- base URL normalization and loopback detection
- GET `/v1/models`
- model list and model selection
- optional bearer token
- connection-state errors
- non-loopback privacy warning
- mocked network tests through an injected transport

Do not implement:
- chat completions
- snapshot generation
- sessions
- observation
- janitor model UI

Acceptance criteria:
- base URL and selected model persist
- API token does not exist in SQLite, logs, or source files
- empty token omits Authorization
- token sends a bearer header
- server, auth, empty-model, and invalid-response states are distinct
- non-loopback address produces a visible warning
- tests and full check pass

Commit:
`feat: add LM Studio settings and model discovery`
